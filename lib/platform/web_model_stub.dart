import 'dart:ui' show Rect;

/// Pengganti untuk target non-web. Tidak pernah dipanggil: scanner hanya
/// menyentuh jalur ini di balik `kIsWeb`.
bool setWebModelSrc(String url) => false;

void setWebModelRect(Rect rect) {}

void setWebModelVisible(bool visible) {}

void setWebModelSize(double px) {}

void onWebModelReady(void Function(int ms) cb) {}
