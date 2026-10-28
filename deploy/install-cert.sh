#!/usr/bin/env bash
#
# Memasang sertifikat dari CA internal perusahaan ke VPS.
#
# Dijalankan dari MESIN LOKAL, menunjuk berkas .crt dan .key yang kamu punya:
#
#   VPS_HOST=user@10.30.12.65 ./deploy/install-cert.sh ~/Downloads/imago.crt ~/Downloads/imago.key
#
# Semua pemeriksaan di bawah dilakukan SEBELUM berkas dikirim, karena kesalahan
# sertifikat tidak terlihat di tempat yang masuk akal: halamannya terbuka di
# laptop, lalu kameranya mati di HP, dan gejalanya tampak seperti bug aplikasi.
set -euo pipefail

CRT="${1:?Berikan path berkas .crt sebagai argumen pertama}"
KEY="${2:?Berikan path berkas .key sebagai argumen kedua}"
VPS_HOST="${VPS_HOST:?Set VPS_HOST, misal: VPS_HOST=svr-app-prd-imago@10.30.12.65}"
REMOTE_DIR="${REMOTE_DIR:-/srv/imago}"

for f in "$CRT" "$KEY"; do
  [ -f "$f" ] || { echo "Tidak ditemukan: $f" >&2; exit 1; }
done

echo "==> Periksa format"
if ! grep -q 'BEGIN CERTIFICATE' "$CRT"; then
  cat >&2 <<MSG
!! $CRT bukan PEM.

   Kalau berkasmu .pfx atau .p12 (lazim dari CA Windows/AD), ubah dulu:

     openssl pkcs12 -in berkas.pfx -nokeys  -nodes -out imago.crt
     openssl pkcs12 -in berkas.pfx -nocerts -nodes -out imago.key
MSG
  exit 1
fi
grep -q 'PRIVATE KEY' "$KEY" || { echo "!! $KEY bukan kunci privat PEM." >&2; exit 1; }

echo "==> Periksa rantai"
JUMLAH=$(grep -c 'BEGIN CERTIFICATE' "$CRT")
echo "    $JUMLAH sertifikat di dalam berkas"
if [ "$JUMLAH" -lt 2 ]; then
  cat >&2 <<'MSG'

!! Hanya ada satu sertifikat — perantaranya kemungkinan belum disertakan.

   Browser desktop sering tetap menerima karena sudah meng-cache perantara itu
   dari situs lain, tapi Android MENOLAK dan kameranya ikut mati. Gabungkan
   dengan urutan leaf lebih dulu:

     cat leaf.crt intermediate.crt > imago.crt

   Lanjutkan hanya kalau CA-mu memang tanpa perantara.
MSG
  read -r -p "    Tetap lanjut? [y/N] " jwb
  [ "$jwb" = "y" ] || [ "$jwb" = "Y" ] || exit 1
fi

echo "==> Periksa kunci dan sertifikat sepasang"
HC=$(openssl x509 -in "$CRT" -noout -pubkey 2>/dev/null | openssl md5)
HK=$(openssl pkey -in "$KEY" -pubout 2>/dev/null | openssl md5)
if [ "$HC" != "$HK" ]; then
  echo "!! Kunci TIDAK cocok dengan sertifikat. Caddy akan menolak memuatnya." >&2
  exit 1
fi
echo "    cocok"

echo "==> Identitas sertifikat"
openssl x509 -in "$CRT" -noout -subject -issuer -dates \
  | sed 's/^/    /'
echo "    nama yang dicakup:"
openssl x509 -in "$CRT" -noout -ext subjectAltName 2>/dev/null \
  | grep -v 'X509v3' | sed 's/^/    /' || echo "    (tidak ada SAN)"

cat <<'MSG'

    Pastikan salah satu nama di atas PERSIS sama dengan DOMAIN di .env.
    Sertifikat untuk nama lain akan ditolak browser, dan kameranya ikut mati.

MSG
read -r -p "    Kirim ke VPS sekarang? [y/N] " lanjut
[ "$lanjut" = "y" ] || [ "$lanjut" = "Y" ] || exit 1

echo "==> Kirim"
ssh "$VPS_HOST" "mkdir -p '$REMOTE_DIR/certs' && chmod 700 '$REMOTE_DIR/certs'"
scp "$CRT" "$VPS_HOST:$REMOTE_DIR/certs/imago.crt"
scp "$KEY" "$VPS_HOST:$REMOTE_DIR/certs/imago.key"
ssh "$VPS_HOST" "chmod 600 '$REMOTE_DIR/certs/imago.key'"

cat <<MSG

Selesai. Satu langkah lagi di VPS — set sumber sertifikatnya, lalu nyalakan:

  sed -i 's#^TLS_MODE=.*#TLS_MODE=/certs/imago.crt /certs/imago.key#' $REMOTE_DIR/.env \\
    || echo 'TLS_MODE=/certs/imago.crt /certs/imago.key' >> $REMOTE_DIR/.env

  cd $REMOTE_DIR && sudo docker compose up -d && sudo docker compose logs --tail=20 caddy

MSG
