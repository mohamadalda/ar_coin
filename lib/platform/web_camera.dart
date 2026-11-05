/// Kamera web, di belakang satu pintu.
///
/// Di mobile seluruh implementasi webnya menguap: `dart.library.js_interop`
/// bernilai false di VM (lihat libraries.json — target `vm` tidak
/// menyediakannya), jadi yang terpilih adalah stub. Karena itu jalur kamera
/// mobile di scanner_screen tidak tersentuh sama sekali oleh port ini.
library;

import 'web_camera_result.dart';
import 'web_camera_stub.dart'
    if (dart.library.js_interop) 'web_camera_web.dart' as impl;

export 'web_camera_result.dart';

/// Meminta izin dan menyalakan kamera. Di web, getUserMedia itu sendiri yang
/// menjadi prompt izinnya — `permission_handler` tidak punya implementasi web
/// dan selalu menjawab "denied", jadi paket itu tidak boleh dipakai di sini.
Future<WebCameraResult> startWebCamera() => impl.startWebCamera();

/// Mematikan kamera dan menyembunyikan lapisan videonya.
void stopWebCamera() => impl.stopWebCamera();

/// Ukuran sumber video saat ini, 0x0 bila belum siap.
WebCameraResult webCameraSize() => impl.webCameraSize();
