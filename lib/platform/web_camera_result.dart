/// Hasil upaya menyalakan kamera web.
///
/// Tipe ini sengaja bebas platform supaya bisa dipakai bersama oleh stub
/// (mobile) dan implementasi web tanpa salah satunya menarik `dart:js_interop`.
class WebCameraResult {
  /// True bila kamera menyala dan preview sudah tampil.
  final bool ok;

  /// Nama kesalahan apa adanya dari browser bila [ok] false.
  ///
  /// Nilai yang mungkin muncul dan artinya bagi pengguna:
  ///   NotAllowedError              — izin ditolak
  ///   NotFoundError                — tidak ada kamera
  ///   NotReadableError             — kamera dipakai aplikasi lain
  ///   InsecureContextOrUnsupported — dibuka lewat http non-localhost
  final String? error;

  /// Ukuran sumber video, dalam piksel. Inilah ruang koordinat tempat kotak
  /// koin dilaporkan, sehingga pemetaan ke layar sama persis dengan mobile.
  final int width;
  final int height;

  const WebCameraResult({
    required this.ok,
    this.error,
    this.width = 0,
    this.height = 0,
  });

  static const WebCameraResult unsupported =
      WebCameraResult(ok: false, error: 'NotWeb');
}
