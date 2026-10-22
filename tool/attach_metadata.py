"""Menempelkan metadata ke model TFLite hasil export Teachable Machine.

WAJIB dijalankan setiap kali model dilatih ulang. Tanpa ini ML Kit menolak
modelnya dengan:

    MlKitException: Failed to initialize detector. Input tensor has type
    kTfLiteFloat32: it requires specifying NormalizationOptions metadata

Kegagalannya senyap di aplikasi — image labeling sekadar mati, tanpa pesan
apa pun di layar.

Pakai lewat tool/attach_metadata.sh, jangan dipanggil langsung.
"""
import os
import shutil
import sys

from tflite_support import flatbuffers
from tflite_support import metadata as _metadata
from tflite_support import metadata_schema_py_generated as fb

src, labels_path, out = sys.argv[1], sys.argv[2], sys.argv[3]

# ML Kit hanya menerima classifier gambar 3 kanal (RGB). Export "TensorFlow
# Lite for Microcontrollers" dari Teachable Machine menghasilkan 96x96x1
# grayscale, dan itu tidak akan pernah jalan — lebih baik ditolak di sini
# daripada gagal senyap di perangkat.
import struct as _struct
_raw = open(src, 'rb').read()
_shapes = [(s, c) for s in (96, 128, 160, 192, 224, 256) for c in (1, 3)
           if _struct.pack('<4i', 1, s, s, c) in _raw]
if _shapes and all(c != 3 for _, c in _shapes):
    sys.exit(
        f"\nBentuk input model: {_shapes[0][0]}x{_shapes[0][0]}x{_shapes[0][1]} "
        "(grayscale).\nML Kit menuntut classifier 3 kanal RGB.\n\n"
        "Ini BUKAN soal tab export. Model 96x96 grayscale berarti project\n"
        "Teachable Machine-nya bertipe 'Tiny Image Project' -- ukuran dan\n"
        "grayscale itu melekat pada project, sehingga SEMUA opsi export\n"
        "menghasilkan bentuk yang sama.\n\n"
        "Yang harus dilakukan: buat project BARU di Teachable Machine,\n"
        "pilih 'Image Project' -> 'Standard image model', unggah ulang foto\n"
        "dari sumber aslinya (bukan dari berkas .tm, karena foto di dalamnya\n"
        "sudah ikut dikecilkan ke 96x96), latih, lalu export lewat\n"
        "'Tensorflow Lite' -> 'Floating point'. Hasilnya: model_unquant.tflite\n"
        "dengan input 1x224x224x3.\n"
    )

m = fb.ModelMetadataT()
m.name = 'IMAGO classifier'
m.description = 'Klasifikasi koin Rupiah dan sosok mitologi Bali'
m.version = 'v1'

inp = fb.TensorMetadataT()
inp.name = 'image'
inp.description = 'Gambar input 224x224 RGB'
inp.content = fb.ContentT()
inp.content.contentProperties = fb.ImagePropertiesT()
inp.content.contentProperties.colorSpace = fb.ColorSpaceType.RGB
inp.content.contentPropertiesType = fb.ContentProperties.ImageProperties

norm = fb.ProcessUnitT()
norm.optionsType = fb.ProcessUnitOptions.NormalizationOptions
norm.options = fb.NormalizationOptionsT()
# Teachable Machine melatih dengan input dinormalisasi ke [-1, 1].
# Angka ini HARUS persis; salah sedikit, akurasinya anjlok tanpa error.
norm.options.mean = [127.5]
norm.options.std = [127.5]
inp.processUnits = [norm]

st = fb.StatsT()
st.max, st.min = [255.0], [0.0]
inp.stats = st

out_meta = fb.TensorMetadataT()
out_meta.name = 'probability'
out_meta.description = 'Probabilitas tiap kelas'
out_meta.content = fb.ContentT()
out_meta.content.contentProperties = fb.FeaturePropertiesT()
out_meta.content.contentPropertiesType = fb.ContentProperties.FeatureProperties
so = fb.StatsT()
so.max, so.min = [1.0], [0.0]
out_meta.stats = so

lf = fb.AssociatedFileT()
lf.name = 'labels.txt'
lf.description = 'Nama kelas'
lf.type = fb.AssociatedFileType.TENSOR_AXIS_LABELS
out_meta.associatedFiles = [lf]

sg = fb.SubGraphMetadataT()
sg.inputTensorMetadata = [inp]
sg.outputTensorMetadata = [out_meta]
m.subgraphMetadata = [sg]

b = flatbuffers.Builder(0)
b.Finish(m.Pack(b), _metadata.MetadataPopulator.METADATA_FILE_IDENTIFIER)

# Lewat berkas sementara, supaya aman walau src dan out adalah berkas yang
# sama — memperbaiki model yang sudah terlanjur dipasang di assets.
import tempfile
tmp = os.path.join(tempfile.gettempdir(), 'attach_metadata_work.tflite')
shutil.copy(src, tmp)
p = _metadata.MetadataPopulator.with_model_file(tmp)
p.load_metadata_buffer(b.Output())
p.load_associated_files([labels_path])
try:
    p.populate()
except ValueError as e:
    if 'already been packed' in str(e):
        sys.exit(
            "\nModel ini sudah punya metadata.\n"
            "Pakai berkas mentah hasil export Teachable Machine\n"
            "(model_unquant.tflite), bukan assets/coin_model.tflite.\n"
        )
    raise

shutil.copy(tmp, out)
os.remove(tmp)

d = _metadata.MetadataDisplayer.with_model_file(out)
import json
sub = json.loads(d.get_metadata_json())['subgraph_metadata'][0]
print('OK ->', out)
print('  normalisasi :', sub['input_tensor_metadata'][0]['process_units'][0]['options'])
print('  label       :', open(labels_path).read().split())
