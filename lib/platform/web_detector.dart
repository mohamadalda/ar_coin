/// Detektor koin web, di belakang satu pintu.
///
/// Seperti web_camera.dart, implementasinya tidak pernah dikompilasi di mobile
/// karena `dart.library.js_interop` bernilai false di target VM.
library;

import 'dart:ui' show Rect;

import 'coin_observation.dart';
import 'web_detector_stub.dart'
    if (dart.library.js_interop) 'web_detector_web.dart' as impl;

export 'coin_observation.dart';

/// Memuat MediaPipe dan membangun classifier dari [modelPath].
///
/// Mengembalikan null bila berhasil, atau pesan kesalahan bila gagal — yang
/// paling sering karena tidak ada koneksi saat mengambil runtime MediaPipe.
/// Kegagalan di sini TIDAK fatal: aplikasi tetap berjalan tanpa deteksi.
Future<String?> initWebDetector(String modelPath) =>
    impl.initWebDetector(modelPath);

/// Menetapkan daerah yang diklasifikasi, dalam koordinat piksel video.
void setWebDetectorRoi(Rect roi) => impl.setWebDetectorRoi(roi);

/// Mendaftarkan penerima hasil. Dipanggil sekali; detektor yang mendorong.
void onWebDetectorResult(void Function(CoinObservation) cb) =>
    impl.onWebDetectorResult(cb);

void startWebDetector() => impl.startWebDetector();

void stopWebDetector() => impl.stopWebDetector();
