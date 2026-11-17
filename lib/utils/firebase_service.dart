import 'package:firebase_app_check/firebase_app_check.dart';
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

      // Harus setelah initializeApp dan sebelum panggilan Auth/Firestore
      // pertama: begitu enforcement menyala, permintaan tanpa token App Check
      // ditolak 401 sebelum kredensial sempat diperiksa.
      await _aktifkanAppCheck();
    } catch (e) {
      _ready = false;
      _lastError = '$e';
      debugPrint('ℹ️ Firebase tidak aktif, memakai penyimpanan lokal: $e');
    }
  }

  /// Alasan App Check gagal diaktifkan, atau null bila aman.
  static String? get appCheckError => _appCheckError;
  static String? _appCheckError;

  /// Memasang penyedia bukti-keaslian aplikasi.
  ///
  /// Di rilis, Android memakai Play Integrity dan Apple memakai App Attest.
  /// Di build debug keduanya memakai penyedia debug, karena Play Integrity
  /// hanya mengenali APK yang ditandatangani Play dan App Attest hanya
  /// mengenali build dari TestFlight/App Store — tanpa ini, setiap sesi
  /// pengembangan akan ditolak.
  ///
  /// Kegagalan di sini TIDAK fatal, mengikuti aturan kelas ini. Tapi perlu
  /// dicatat: bila enforcement sudah menyala di console sementara aktivasi di
  /// sini gagal, gejalanya muncul jauh dari sebabnya — sebagai "sandi salah"
  /// di layar login.
  static Future<void> _aktifkanAppCheck() async {
    try {
      if (kIsWeb && kWebRecaptchaSiteKey == null) {
        _appCheckError = 'Site key reCAPTCHA belum diisi, App Check web '
            'dilewati (lihat lib/firebase_options_web.dart)';
        debugPrint('ℹ️ $_appCheckError');
        return;
      }

      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
        providerApple: kDebugMode
            ? const AppleDebugProvider()
            : const AppleAppAttestProvider(),
        providerWeb: kWebRecaptchaSiteKey == null
            ? null
            : ReCaptchaV3Provider(kWebRecaptchaSiteKey!),
      );
      _appCheckError = null;
      debugPrint('✅ App Check aktif (${kDebugMode ? 'debug' : 'rilis'})');
    } catch (e) {
      _appCheckError = '$e';
      debugPrint('⚠️ App Check gagal diaktifkan: $e');
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
