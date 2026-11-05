import 'dart:ui' show Rect, Size;

/// Satu hasil pengamatan dari detektor koin.
///
/// Tipe ini bebas platform. Koordinat [box] berada dalam ruang SUMBER GAMBAR
/// dengan orientasi tegak — ruang yang sama dengan [sourceSize] — sehingga
/// pemetaan ke layar lewat `_trackedRectOnScreen()` tidak perlu tahu backend
/// mana yang menghasilkannya. Itulah ujinya: kalau kedua platform jujur
/// melaporkan kotak dan ukuran sumber dengan konvensi yang sama, matematika
/// cover-fit-nya tidak peduli siapa pengirimnya.
class CoinObservation {
  /// Label kelas teratas. Kosong bila tidak ada yang terklasifikasi.
  final String label;

  final double confidence;

  /// Kotak koin dalam koordinat sumber. Null bila lokalisasi tidak
  /// menghasilkan apa pun.
  final Rect? box;

  /// True bila [box] adalah koin yang benar-benar ditemukan pencocokan bentuk.
  /// False berarti ia sekadar daerah pencarian, dan posisi aset sebaiknya
  /// tidak diperbarui darinya.
  final bool located;

  /// Ukuran sumber tempat [box] dinyatakan.
  final Size sourceSize;

  /// Apakah ada sesuatu selain latar di dalam daerah yang diperiksa.
  /// Membedakan dua batas frame hilang yang berbeda di scanner.
  final bool sawAnyObject;

  /// Lama inferensi satu frame, untuk penyetelan dan pencatatan uji.
  final int latencyMs;

  const CoinObservation({
    required this.label,
    required this.confidence,
    required this.box,
    required this.located,
    required this.sourceSize,
    required this.sawAnyObject,
    required this.latencyMs,
  });
}
