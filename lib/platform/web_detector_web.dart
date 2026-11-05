import 'dart:js_interop';
import 'dart:ui' show Rect, Size;

import 'coin_observation.dart';

/// Jembatan ke `window.ImagoDetector` (web/imago_detector.js).
///
/// Piksel tidak pernah menyeberang: yang melintas hanya objek hasil sekitar
/// seratus byte per frame. Frame 640x480 RGBA akan berarti ~1,2 MB penyalinan
/// per frame kalau dibawa ke Dart.

@JS('ImagoDetector.init')
external JSPromise<_JsInitResult> _init(JSString modelPath);

@JS('ImagoDetector.setRoi')
external void _setRoi(JSNumber x, JSNumber y, JSNumber w, JSNumber h);

@JS('ImagoDetector.onResult')
external void _onResult(JSFunction cb);

@JS('ImagoDetector.start')
external void _start();

@JS('ImagoDetector.stop')
external void _stop();

extension type _JsInitResult._(JSObject _) implements JSObject {
  external bool get ok;
  external String? get error;
}

extension type _JsObservation._(JSObject _) implements JSObject {
  external String get label;
  external double get confidence;
  external double get x;
  external double get y;
  external double get w;
  external double get h;
  external bool get located;
  external double get srcW;
  external double get srcH;
  external bool get sawAnyObject;
  external int get tMs;
}

Future<String?> initWebDetector(String modelPath) async {
  try {
    final r = await _init(modelPath.toJS).toDart;
    return r.ok ? null : (r.error ?? 'UnknownError');
  } catch (e) {
    return '$e';
  }
}

void setWebDetectorRoi(Rect roi) => _setRoi(
      roi.left.toJS,
      roi.top.toJS,
      roi.width.toJS,
      roi.height.toJS,
    );

void onWebDetectorResult(void Function(CoinObservation) cb) {
  _onResult(((_JsObservation r) {
    cb(CoinObservation(
      label: r.label,
      confidence: r.confidence,
      box: r.w > 0 && r.h > 0 ? Rect.fromLTWH(r.x, r.y, r.w, r.h) : null,
      located: r.located,
      sourceSize: Size(r.srcW, r.srcH),
      sawAnyObject: r.sawAnyObject,
      latencyMs: r.tMs,
    ));
  }).toJS);
}

void startWebDetector() => _start();

void stopWebDetector() => _stop();
