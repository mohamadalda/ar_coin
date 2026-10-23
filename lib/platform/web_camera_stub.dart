import 'web_camera_result.dart';

/// Implementasi pengganti untuk target non-web (Android, iOS).
///
/// Tidak pernah dipanggil: scanner_screen hanya menyentuh jalur ini di balik
/// `kIsWeb`. Keberadaannya semata agar `lib/platform/web_camera.dart` bisa
/// dikompilasi di mobile tanpa menarik `dart:js_interop`.
Future<WebCameraResult> startWebCamera() async => WebCameraResult.unsupported;

void stopWebCamera() {}

WebCameraResult webCameraSize() => WebCameraResult.unsupported;
