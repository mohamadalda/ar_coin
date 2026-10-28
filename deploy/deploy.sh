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

echo "==> Build web"
flutter build web --release

# Pemeriksaan ini ada karena kegagalannya tidak kelihatan sampai demo:
# aplikasi tetap tampil normal, hanya scanner-nya yang diam saja.
if ! grep -q "kWebFirebaseOptions = FirebaseOptions" lib/firebase_options_web.dart; then
  echo "!! lib/firebase_options_web.dart belum diisi — web akan jalan tanpa Firebase." >&2
fi

echo "==> Kirim konfigurasi"
ssh $SSH_OPTS "$VPS_HOST" "mkdir -p '$REMOTE_DIR/web'"
rsync -az -e "ssh $SSH_OPTS" deploy/Caddyfile deploy/docker-compose.yml \
  "$VPS_HOST:$REMOTE_DIR/"

echo "==> Kirim hasil build"
# --delete penting: tanpa itu berkas yang sudah dihapus dari build tetap
# tertinggal di server dan ikut terlayani selamanya.
rsync -az --delete $PROGRESS -e "ssh $SSH_OPTS" \
  build/web/ "$VPS_HOST:$REMOTE_DIR/web/"

echo "==> Nyalakan ulang container"
ssh $SSH_OPTS "$VPS_HOST" "cd '$REMOTE_DIR' && $DOCKER_CMD compose up -d"

echo
echo "Selesai. Buka https://\$DOMAIN di HP dan izinkan kamera."
echo "Kalau sertifikat belum terbit, lihat: ssh $VPS_HOST 'cd $REMOTE_DIR && $DOCKER_CMD compose logs -f caddy'"
