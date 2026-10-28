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
ssh "$VPS_HOST" "mkdir -p '$REMOTE_DIR/web'"
rsync -az deploy/Caddyfile deploy/docker-compose.yml "$VPS_HOST:$REMOTE_DIR/"

echo "==> Kirim hasil build"
# --delete penting: tanpa itu berkas yang sudah dihapus dari build tetap
# tertinggal di server dan ikut terlayani selamanya.
rsync -az --delete --info=progress2 build/web/ "$VPS_HOST:$REMOTE_DIR/web/"

echo "==> Nyalakan ulang container"
ssh "$VPS_HOST" "cd '$REMOTE_DIR' && docker compose up -d"

echo
echo "Selesai. Buka https://\$DOMAIN di HP dan izinkan kamera."
echo "Kalau sertifikat belum terbit, lihat: ssh $VPS_HOST 'cd $REMOTE_DIR && docker compose logs -f caddy'"
