import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../firebase_options_web.dart';

/// Penyambung ke Firebase yang BOLEH gagal.
///
/// Aplikasi ini harus tetap berfungsi penuh tanpa Firebase: berkas konfigurasi
/// (`GoogleService-Info.plist` / `google-services.json`) hanya ada setelah
/// project dibuat di console, dan demo di ruang sidang bisa saja tanpa sinyal.
/// Karena itu kegagalan inisialisasi tidak dianggap fatal — [ready] menjadi
/// false dan seluruh fitur jatuh kembali ke penyimpanan lokal.
class FirebaseService {
  static bool _ready = false;
  static String? _lastError;

  /// True hanya bila Firebase benar-benar siap dipakai.
  static bool get ready => _ready;

  /// Alasan Firebase tidak aktif, untuk ditampilkan di strip diagnostik.
  /// Null bila [ready] true.
  static String? get lastError => _lastError;

  static Future<void> init() async {
    try {
      if (kIsWeb) {
        // Web tidak punya google-services.json yang ikut ter-bundle, jadi
        // opsinya harus ditanam di kode. Lihat lib/firebase_options_web.dart.
        if (kWebFirebaseOptions == null) {
          _ready = false;
          _lastError = 'Web app belum didaftarkan di Firebase Console '
              '(lihat lib/firebase_options_web.dart)';
          debugPrint('Firebase tidak aktif di web: $_lastError');
          return;
        }
        await Firebase.initializeApp(options: kWebFirebaseOptions);
      } else {
        // Jalur mobile TIDAK BERUBAH: konfigurasi dibaca dari
        // google-services.json / GoogleService-Info.plist seperti semula.
        await Firebase.initializeApp();
      }
      _ready = true;
      _lastError = null;
      debugPrint('✅ Firebase siap');
    } catch (e) {
      _ready = false;
      _lastError = '$e';
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
