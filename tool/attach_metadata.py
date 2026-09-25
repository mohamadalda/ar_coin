"""Menempelkan metadata ke model TFLite hasil export Teachable Machine.

WAJIB dijalankan setiap kali model dilatih ulang. Tanpa ini ML Kit menolak
modelnya dengan:

    MlKitException: Failed to initialize detector. Input tensor has type
    kTfLiteFloat32: it requires specifying NormalizationOptions metadata

Kegagalannya senyap di aplikasi — image labeling sekadar mati, tanpa pesan
apa pun di layar.

Pakai lewat tool/attach_metadata.sh, jangan dipanggil langsung.
"""
import shutil
import sys

from tflite_support import flatbuffers
from tflite_support import metadata as _metadata
from tflite_support import metadata_schema_py_generated as fb

src, labels_path, out = sys.argv[1], sys.argv[2], sys.argv[3]

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

shutil.copy(src, out)
p = _metadata.MetadataPopulator.with_model_file(out)
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

d = _metadata.MetadataDisplayer.with_model_file(out)
import json
sub = json.loads(d.get_metadata_json())['subgraph_metadata'][0]
print('OK ->', out)
print('  normalisasi :', sub['input_tensor_metadata'][0]['process_units'][0]['options'])
print('  label       :', open(labels_path).read().split())
