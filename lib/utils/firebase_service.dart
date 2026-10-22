import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Penyambung ke Firebase yang BOLEH gagal.
///
/// Aplikasi ini harus tetap berfungsi penuh tanpa Firebase: berkas konfigurasi
/// (`GoogleService-Info.plist` / `google-services.json`) hanya ada setelah
/// project dibuat di console, dan demo di ruang sidang bisa saja tanpa sinyal.
/// Karena itu kegagalan inisialisasi tidak dianggap fatal — [ready] menjadi
/// false dan seluruh fitur jatuh kembali ke penyimpanan lokal.
class FirebaseService {
  static bool _ready = false;

  /// True hanya bila Firebase benar-benar siap dipakai.
  static bool get ready => _ready;

  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
      _ready = true;
      debugPrint('✅ Firebase siap');
    } catch (e) {
      _ready = false;
      debugPrint('ℹ️ Firebase tidak aktif, memakai penyimpanan lokal: $e');
    }
  }

  /// Kunci dokumen yang stabil dari nama hero. Dipakai agar pembaruan dan
  /// penghapusan menunjuk dokumen yang sama, bukan membuat salinan baru.
  static String docIdFor(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.isEmpty ? 'hero' : slug;
  }
}
