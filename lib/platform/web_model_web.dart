import 'dart:js_interop';
import 'dart:ui' show Rect;

/// Jembatan ke `window.ImagoModel` (web/imago_model.js).

@JS('ImagoModel.setSrc')
external bool _setSrc(JSString url);

@JS('ImagoModel.setRect')
external void _setRect(JSNumber l, JSNumber t, JSNumber w, JSNumber h);

@JS('ImagoModel.setVisible')
external void _setVisible(JSBoolean visible);

@JS('ImagoModel.setSize')
external void _setSize(JSNumber px);

@JS('ImagoModel.onReady')
external void _onReady(JSFunction cb);

bool setWebModelSrc(String url) => _setSrc(url.toJS);

void setWebModelRect(Rect rect) => _setRect(
      rect.left.toJS,
      rect.top.toJS,
      rect.width.toJS,
      rect.height.toJS,
    );

void setWebModelVisible(bool visible) => _setVisible(visible.toJS);

void setWebModelSize(double px) => _setSize(px.toJS);

void onWebModelReady(void Function(int ms) cb) {
  _onReady(((JSNumber ms) => cb(ms.toDartInt)).toJS);
}
