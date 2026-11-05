#!/usr/bin/env bash
#
# Deploy IMAGO web ke VPS.
#
# Dijalankan dari MESIN LOKAL, bukan dari VPS: Flutter SDK tidak perlu ada di
# server. Yang dikirim hanya hasil build.
#
#   VPS_HOST=user@1.2.3.4 ./deploy/deploy.sh
#
set -euo pipefail

VPS_HOST="${VPS_HOST:?Set VPS_HOST dulu, misal: VPS_HOST=root@1.2.3.4 ./deploy/deploy.sh}"
REMOTE_DIR="${REMOTE_DIR:-/srv/imago}"

# Perintah docker di VPS. Kalau user SSH-mu belum masuk grup `docker`, jalankan
# dengan DOCKER_CMD="sudo docker" — tapi sudo lewat SSH non-interaktif hanya
# berhasil bila user itu boleh sudo tanpa kata sandi.
DOCKER_CMD="${DOCKER_CMD:-docker}"

# sudo menolak berjalan tanpa terminal ketika ia perlu menanyakan kata sandi,
# dan ssh non-interaktif memang tidak menyediakannya. Jadi khusus saat
# DOCKER_CMD memakai sudo, mintakan terminal dengan -t.
SSH_TTY_FLAG=""
case "$DOCKER_CMD" in
  sudo*) SSH_TTY_FLAG="-t" ;;
esac

# Satu koneksi SSH dipakai ulang untuk semua langkah di bawah. Tanpa ini,
# tiap ssh dan rsync membuka koneksi sendiri dan meminta kata sandi lagi —
# empat kali untuk satu kali deploy.
SSH_CTL="$HOME/.ssh/cm-imago-%h"
SSH_OPTS="-o ControlMaster=auto -o ControlPath=$SSH_CTL -o ControlPersist=120"
mkdir -p "$HOME/.ssh"

# --info=progress2 hanya ada di rsync GNU. macOS 15 ke atas mengapalkan
# openrsync, yang menolaknya dan menggagalkan seluruh transfer.
if rsync --help 2>&1 | grep -q -- '--info'; then
  PROGRESS="--info=progress2"
else
  PROGRESS="--progress"
fi
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$REPO_DIR"

echo "==> Ambil pustaka web (diperiksa SHA-256)"
bash tool/fetch_web_vendor.sh

echo "==> Build web"
# --no-web-resources-cdn: CanvasKit ikut di build/web dan dimuat dari server
# sendiri, bukan dari www.gstatic.com (pentest IMAGO temuan 10).
flutter build web --release --no-web-resources-cdn

# version.json hanya membocorkan versi aplikasi (temuan 9) dan tidak dipakai
# aplikasi ini. Caddy juga menolaknya, tapi lebih baik tidak ikut terkirim.
rm -f build/web/version.json

# Pemeriksaan akhir: tidak boleh ada rujukan CDN tersisa di halaman utama.
if grep -qE 'cdn\.jsdelivr\.net|unpkg\.com' build/web/index.html build/web/*.js; then
  echo "!! build/web masih memuat pustaka dari CDN publik." >&2
  exit 1
fi

# Pemeriksaan ini ada karena kegagalannya tidak kelihatan sampai demo:
# aplikasi tetap tampil normal, hanya scanner-nya yang diam saja.
if ! grep -q "kWebFirebaseOptions = FirebaseOptions" lib/firebase_options_web.dart; then
  echo "!! lib/firebase_options_web.dart belum diisi — web akan jalan tanpa Firebase." >&2
fi

echo "==> Kirim konfigurasi"
ssh $SSH_OPTS "$VPS_HOST" "mkdir -p '$REMOTE_DIR/web'"
rsync -az -e "ssh $SSH_OPTS" \
  deploy/Caddyfile deploy/docker-compose.yml deploy/.env.example \
  "$VPS_HOST:$REMOTE_DIR/"

# .env menentukan domain mana yang dilayani. Tanpa berkas itu, {$DOMAIN} di
# Caddyfile menjadi string kosong, Caddy gagal mengurai konfigurasinya, dan
# container masuk restart loop — gejala yang tidak menyebut .env sama sekali,
# jadi lebih baik dihentikan di sini dengan pesan yang jelas.
if ! ssh $SSH_OPTS "$VPS_HOST" "test -f '$REMOTE_DIR/.env'"; then
  cat >&2 <<MSG

!! $REMOTE_DIR/.env belum ada di VPS.

   Buat dulu di sana, lalu jalankan skrip ini lagi:

     cat > $REMOTE_DIR/.env <<'EOF'
     DOMAIN=imago.domainmu.com
     ACME_EMAIL=email-kamu@contoh.com
     EOF

MSG
  exit 1
fi

echo "==> Kirim hasil build"
# --delete penting: tanpa itu berkas yang sudah dihapus dari build tetap
# tertinggal di server dan ikut terlayani selamanya.
rsync -az --delete $PROGRESS -e "ssh $SSH_OPTS" \
  build/web/ "$VPS_HOST:$REMOTE_DIR/web/"

echo "==> Nyalakan ulang container"
ssh $SSH_OPTS $SSH_TTY_FLAG "$VPS_HOST" "cd '$REMOTE_DIR' && $DOCKER_CMD compose up -d"

echo
echo "Selesai. Buka https://\$DOMAIN di HP dan izinkan kamera."
echo "Kalau sertifikat belum terbit, lihat: ssh $VPS_HOST 'cd $REMOTE_DIR && $DOCKER_CMD compose logs -f caddy'"
