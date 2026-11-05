#!/usr/bin/env bash
#
# Mengambil pustaka pihak ketiga untuk build web ke web/vendor/, supaya
# browser pengguna memuatnya dari server IMAGO sendiri, bukan dari CDN publik
# (pentest IMAGO temuan 10, CWE-494).
#
# Setiap berkas DIPERIKSA SHA-256-nya terhadap nilai yang dikunci di bawah.
# Bila CDN pernah mengirim isi yang berbeda — diretas, disusupi di jalan, atau
# versinya diganti diam-diam — skrip berhenti dan build tidak dilanjutkan.
# Pemeriksaan ini terjadi SEKALI saat build, bukan di setiap browser.
#
# Dijalankan otomatis oleh deploy/deploy.sh. Untuk `flutter run -d chrome`
# jalankan sekali secara manual:
#
#   bash tool/fetch_web_vendor.sh
#
# Menaikkan versi: ubah versi di URL, jalankan dengan UPDATE_HASHES=1 untuk
# mencetak hash baru, TINJAU perubahannya, lalu salin hash itu ke tabel ini.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$REPO_DIR/web/vendor"

MP_VER=0.10.14
MV_VER=4.4.0
# HARUS sama dengan supportedFirebaseJsSdkVersion milik firebase_core_web di
# pubspec.lock; versi lain tidak diuji FlutterFire.
FB_VER=13.0.0

MP=https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@$MP_VER
MV=https://cdn.jsdelivr.net/npm/@google/model-viewer@$MV_VER/dist
FB=https://www.gstatic.com/firebasejs/$FB_VER

# sha256  url  tujuan (relatif terhadap web/vendor)
MANIFEST="
18b2e711035aa4705ee281530a55dc2338ff05eed3d70ae16d54105282a75ed5 $MV/model-viewer.min.js model-viewer/$MV_VER/model-viewer.min.js
e77f281f9619150d937023c355bae170e9120e3b9e43f1e23a2a7bee07197669 $MP/vision_bundle.mjs mediapipe/$MP_VER/vision_bundle.mjs
9440cf0cc0cea21800e31581ec32aeedcc5fbf9df4509796bbc7d3f99e52ab9c $MP/wasm/vision_wasm_internal.js mediapipe/$MP_VER/wasm/vision_wasm_internal.js
f82a8e6c05e08a44cc9f9e7ec5f845935bcbb1b1500ebe8c2f4812fb4e2917dc $MP/wasm/vision_wasm_internal.wasm mediapipe/$MP_VER/wasm/vision_wasm_internal.wasm
abe9b6fbeaf86fcb53a5edce3926c82ccb0619e18fed4d9d9ce561ee7f55e054 $MP/wasm/vision_wasm_nosimd_internal.js mediapipe/$MP_VER/wasm/vision_wasm_nosimd_internal.js
38b61feab2fd7934e05cbe9f68baa308978a5e3b7f85c1913bb8ae89b8ef8b97 $MP/wasm/vision_wasm_nosimd_internal.wasm mediapipe/$MP_VER/wasm/vision_wasm_nosimd_internal.wasm
7cb48cbc5728f220562d05bd0aab8c17d8bda03c599ad8cb4ad0f042e4f65765 $FB/firebase-app.js firebase/$FB_VER/firebase-app.js
286224de4d870ef55e4301f718488fa77f146d60d6953b3a76f9a3883669b34a $FB/firebase-auth.js firebase/$FB_VER/firebase-auth.js
689fe30b1b7c878d71c808c582703b86355b7efe9e5269bfe129883a6c7d41a9 $FB/firebase-firestore-pipelines.js firebase/$FB_VER/firebase-firestore-pipelines.js
"

if command -v sha256sum >/dev/null 2>&1; then
  sha() { sha256sum "$1" | cut -c1-64; }
else
  sha() { shasum -a 256 "$1" | cut -c1-64; }
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
while read -r want url dest; do
  [ -z "${want:-}" ] && continue
  target="$OUT/$dest"

  # Sudah ada dan cocok: tidak perlu diunduh ulang.
  if [ -f "$target.sha256" ] && [ "$(cat "$target.sha256")" = "$want" ] && [ -f "$target" ]; then
    continue
  fi

  echo "==> $dest"
  curl -fsSL --retry 3 -o "$TMP/f" "$url"
  got="$(sha "$TMP/f")"
  if [ "${UPDATE_HASHES:-0}" = "1" ]; then
    echo "    sha256 $got"
  elif [ "$got" != "$want" ]; then
    echo "!! HASH TIDAK COCOK untuk $url" >&2
    echo "   diharapkan $want" >&2
    echo "   diterima   $got" >&2
    fail=1
    continue
  fi

  mkdir -p "$(dirname "$target")"
  # Bundel Firebase mengimpor firebase-app.js dari gstatic dengan URL absolut.
  # Diarahkan ke salinan lokal di folder yang sama; hash diperiksa SEBELUM
  # penulisan ulang ini.
  case "$dest" in
    firebase/*)
      sed "s#https://www.gstatic.com/firebasejs/$FB_VER/firebase-app.js#./firebase-app.js#g" \
        "$TMP/f" > "$target"
      if grep -q 'www.gstatic.com/firebasejs' "$target"; then
        echo "!! $dest masih merujuk gstatic setelah penulisan ulang" >&2
        fail=1
        continue
      fi
      ;;
    *) cp "$TMP/f" "$target" ;;
  esac
  echo "$want" > "$target.sha256"
done <<< "$MANIFEST"

if [ "$fail" != "0" ]; then
  echo "!! Pustaka web TIDAK lengkap. Build dihentikan." >&2
  exit 1
fi
echo "Pustaka web siap di web/vendor/"
