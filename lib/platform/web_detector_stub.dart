import 'dart:ui' show Rect;

import 'coin_observation.dart';

/// Pengganti untuk target non-web. Tidak pernah dipanggil: scanner hanya
/// menyentuh jalur ini di balik `kIsWeb`.
Future<String?> initWebDetector(String modelPath) async => 'NotWeb';

void setWebDetectorRoi(Rect roi) {}

void onWebDetectorResult(void Function(CoinObservation) cb) {}

void startWebDetector() {}

void stopWebDetector() {}
