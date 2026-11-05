import 'dart:js_interop';

import 'web_camera_result.dart';

/// Jembatan tipis ke `window.ImagoCamera` (web/imago_camera.js).
///
/// Elemen <video>-nya hidup di index.html, di BELAKANG kanvas Flutter, bukan
/// sebagai platform view. Alasannya ada di komentar index.html.

@JS('ImagoCamera.start')
external JSPromise<_JsCameraResult> _start();

@JS('ImagoCamera.stop')
external void _stop();

@JS('ImagoCamera.size')
external _JsSize _size();

extension type _JsCameraResult._(JSObject _) implements JSObject {
  external bool get ok;
  external String? get error;
  external double get width;
  external double get height;
}

extension type _JsSize._(JSObject _) implements JSObject {
  external double get width;
  external double get height;
}

Future<WebCameraResult> startWebCamera() async {
  final r = await _start().toDart;
  return WebCameraResult(
    ok: r.ok,
    error: r.error,
    width: r.width.round(),
    height: r.height.round(),
  );
}

void stopWebCamera() => _stop();

WebCameraResult webCameraSize() {
  final s = _size();
  final w = s.width.round();
  final h = s.height.round();
  return WebCameraResult(ok: w > 0 && h > 0, width: w, height: h);
}
