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
# ssh di Git Bash (Windows) tidak andal dengan soket ControlMaster; di sana
# kata sandi akan ditanyakan di setiap langkah.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) SSH_OPTS="" ;;
esac
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

if [ "${SKIP_BUILD:-0}" = "1" ]; then
  # Dipakai deploy/deploy_windows.ps1: di Windows, flutter yang dipanggil dari
  # Git Bash gagal membaca Pub Cache (dart.exe menerima path gaya MSYS), jadi
  # build dilakukan dari PowerShell lebih dulu dan skrip ini hanya mengirim.
  echo "==> Lewati build (SKIP_BUILD=1), memakai build/web yang ada"
  if [ ! -f build/web/main.dart.js ] || [ ! -f build/web/vendor/firebase/13.0.0/firebase-app.js ]; then
    echo "!! build/web belum lengkap. Jalankan build dulu (deploy/deploy_windows.ps1)." >&2
    exit 1
  fi
else
  echo "==> Ambil pustaka web (diperiksa SHA-256)"
  bash tool/fetch_web_vendor.sh

  echo "==> Build web"
  # --no-web-resources-cdn: CanvasKit ikut di build/web dan dimuat dari server
  # sendiri, bukan dari www.gstatic.com (pentest IMAGO temuan 10).
  flutter build web --release --no-web-resources-cdn
fi

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

# Git Bash di Windows tidak membawa rsync. Tanpanya berkas dikirim sebagai
# arsip tar lewat ssh — hasil akhirnya sama, hanya tanpa pengiriman inkremental.
HAS_RSYNC=1
command -v rsync >/dev/null 2>&1 || HAS_RSYNC=0

echo "==> Kirim konfigurasi"
ssh $SSH_OPTS "$VPS_HOST" "mkdir -p '$REMOTE_DIR/web'"
if [ "$HAS_RSYNC" = 1 ]; then
  rsync -az -e "ssh $SSH_OPTS" \
    deploy/Caddyfile deploy/docker-compose.yml deploy/.env.example \
    "$VPS_HOST:$REMOTE_DIR/"
else
  tar -C deploy -cf - Caddyfile docker-compose.yml .env.example \
    | ssh $SSH_OPTS "$VPS_HOST" "tar -C '$REMOTE_DIR' -xf -"
fi

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
if [ "$HAS_RSYNC" = 1 ]; then
  rsync -az --delete $PROGRESS -e "ssh $SSH_OPTS" \
    build/web/ "$VPS_HOST:$REMOTE_DIR/web/"
else
  # Isi folder dikosongkan lalu diisi ulang DI TEMPAT, bukan folder baru yang
  # ditukar: container memasang ./web lewat bind mount, dan menukar folder
  # membuatnya tetap menyajikan folder lama yang sudah terhapus.
  tar -C build/web -czf - . \
    | ssh $SSH_OPTS "$VPS_HOST" \
        "find '$REMOTE_DIR/web' -mindepth 1 -delete && tar -C '$REMOTE_DIR/web' -xzf -"
fi

echo "==> Nyalakan ulang container"
# --force-recreate: Caddyfile dipasang sebagai bind mount satu berkas, dan
# berkas yang diganti (rsync/tar menulis berkas baru) tidak terlihat oleh
# container yang sudah berjalan. Tanpa ini perubahan Caddyfile tidak berlaku
# sampai container dibuat ulang karena alasan lain.
ssh $SSH_OPTS $SSH_TTY_FLAG "$VPS_HOST" "cd '$REMOTE_DIR' && $DOCKER_CMD compose up -d --force-recreate"

echo
echo "Selesai. Buka https://\$DOMAIN di HP dan izinkan kamera."
echo "Kalau sertifikat belum terbit, lihat: ssh $VPS_HOST 'cd $REMOTE_DIR && $DOCKER_CMD compose logs -f caddy'"
