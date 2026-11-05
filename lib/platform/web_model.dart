/// Aset 3D web, di belakang satu pintu.
///
/// Di mobile seluruh jalur ini tidak terkompilasi; di sana model dirender oleh
/// model_viewer_plus di dalam WebView seperti semula. Alasan web tidak bisa
/// memakai paket yang sama ada di komentar web/imago_model.js.
library;

import 'dart:ui' show Rect;

import 'web_model_stub.dart'
    if (dart.library.js_interop) 'web_model_web.dart' as impl;

/// Mengganti model yang ditampilkan. Mengembalikan true bila benar-benar
/// berganti, sehingga pemanggil tahu kapan harus mereset keadaan "siap".
bool setWebModelSrc(String url) => impl.setWebModelSrc(url);

/// Posisi dan ukuran kotak render dalam piksel logis.
void setWebModelRect(Rect rect) => impl.setWebModelRect(rect);

void setWebModelVisible(bool visible) => impl.setWebModelVisible(visible);

/// Mengunci ukuran tampil model ke tinggi koin dalam piksel.
void setWebModelSize(double px) => impl.setWebModelSize(px);

/// Dipanggil saat model selesai dimuat, dengan lama muat dalam milidetik.
void onWebModelReady(void Function(int ms) cb) => impl.onWebModelReady(cb);
