#!/usr/bin/env bash
# Menempelkan metadata ke model TFLite hasil export Teachable Machine,
# lalu memasangnya ke assets/coin_model.tflite.
#
#   ./tool/attach_metadata.sh ~/Downloads/model_unquant.tflite
#
# Urutan baris di tool/labels.txt HARUS sama dengan urutan kelas di
# Teachable Machine, dan nilainya harus cocok dengan kolom "Label Model"
# tiap hero di halaman Admin.
set -euo pipefail

SRC="${1:?Pakai: ./tool/attach_metadata.sh <model_unquant.tflite>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV="$ROOT/tool/.venv"

if [ ! -x "$VENV/bin/python" ]; then
  echo "Menyiapkan venv sekali jalan..."
  # tflite-support hanya punya wheel untuk Python lama; di 3.12+ pip
  # membangunnya dari source dan hasilnya versi alpha yang masih memakai
  # modul `imp` (dihapus sejak Python 3.12). Shim di bawah menambalnya.
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q --upgrade pip
  "$VENV/bin/pip" install -q tflite-support

  SITE="$("$VENV/bin/python" -c 'import site;print(site.getsitepackages()[0])')"
  cat > "$SITE/imp.py" <<'PYSHIM'
"""Shim minimal untuk `imp`, yang dihapus di Python 3.12.
tflite_support.flatbuffers.compat hanya memakai imp.find_module('numpy')."""
import importlib.util


def find_module(name, path=None):
    spec = importlib.util.find_spec(name)
    if spec is None:
        raise ImportError(name)
    return None, getattr(spec, 'origin', None), ('', '', 5)
PYSHIM
fi

# Teachable Machine selalu menaruh labels.txt di samping modelnya. Kalau ada,
# berkas ITU yang dipakai — urutan kelas langsung dari sumbernya, sehingga tidak
# ada peluang tool/labels.txt tertinggal basi setelah model dilatih ulang.
SRC_LABELS="$(dirname "$SRC")/labels.txt"
if [ -f "$SRC_LABELS" ]; then
  echo "Memakai urutan kelas dari $SRC_LABELS:"
  # Format Teachable Machine berupa "0 barong"; nomornya dibuang.
  sed -E 's/^[0-9]+[[:space:]]+//' "$SRC_LABELS" | sed '/^[[:space:]]*$/d' > "$ROOT/tool/labels.txt"
  sed 's/^/  - /' "$ROOT/tool/labels.txt"
else
  echo "labels.txt tidak ada di samping model; memakai tool/labels.txt apa adanya:"
  sed 's/^/  - /' "$ROOT/tool/labels.txt"
fi
echo

"$VENV/bin/python" "$ROOT/tool/attach_metadata.py" \
  "$SRC" "$ROOT/tool/labels.txt" "$ROOT/assets/coin_model.tflite"

echo
echo "Selesai. Jalankan: flutter build apk --debug && flutter install --debug"
