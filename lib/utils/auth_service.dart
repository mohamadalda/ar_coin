import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_service.dart';

class AuthService {
  static final ValueNotifier<bool> isLoggedIn = ValueNotifier<bool>(false);
  
  // Base64 encoded credentials to avoid plaintext hardcoding
  // admin_imago
  static const String _encodedUsername = 'YWRtaW5faW1hZ28=';
  // imG0menang
  static const String _encodedPassword = 'aW1HMG1lbmFuZw==';

  static const String _loginPrefKey = 'is_admin_logged_in';

  /// Pesan kesalahan terakhir, agar layar login bisa menjelaskan sebabnya
  /// alih-alih sekadar bilang "gagal".
  static String lastError = '';

  static Future<void> init() async {
    // Firebase Auth menyimpan sesinya sendiri. Bila aktif, ia yang menentukan
    // status login; penanda lokal hanya dipakai saat Firebase tidak tersedia.
    if (FirebaseService.ready) {
      isLoggedIn.value = FirebaseAuth.instance.currentUser != null;
      FirebaseAuth.instance.authStateChanges().listen((user) {
        isLoggedIn.value = user != null;
      });
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    isLoggedIn.value = prefs.getBool(_loginPrefKey) ?? false;
  }

  static Future<bool> login(String username, String password) async {
    lastError = '';

    if (FirebaseService.ready) {
      try {
        // Firebase Auth memakai email. Kolom yang sama dipakai agar layar
        // login tidak perlu berubah — isi dengan email admin.
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: username.trim(),
          password: password,
        );
        isLoggedIn.value = true;
        return true;
      } on FirebaseAuthException catch (e) {
        if (_tolakanAppCheck('${e.code} ${e.message}')) {
          lastError = _pesanAppCheck;
          return false;
        }
        lastError = switch (e.code) {
          'invalid-email' => 'Format email tidak valid.',
          'user-not-found' ||
          'wrong-password' ||
          'invalid-credential' =>
            'Email atau kata sandi salah.',
          'network-request-failed' =>
            'Tidak ada koneksi. Login Firebase butuh internet.',
          'too-many-requests' => 'Terlalu banyak percobaan. Coba lagi nanti.',
          _ => 'Login gagal: ${e.code}',
        };
        return false;
      } catch (e) {
        lastError = _tolakanAppCheck('$e') ? _pesanAppCheck : 'Login gagal: $e';
        return false;
      }
    }

    // Jalan mundur: akun lokal, dipakai selama Firebase belum disiapkan.
    final decodedUsername = utf8.decode(base64Decode(_encodedUsername));
    final decodedPassword = utf8.decode(base64Decode(_encodedPassword));

    if (username == decodedUsername && password == decodedPassword) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_loginPrefKey, true);
      isLoggedIn.value = true;
      return true;
    }
    lastError = 'Username atau kata sandi salah.';
    return false;
  }

  /// [GoogleSignIn.initialize] wajib dipanggil tepat satu kali seumur proses;
  /// memanggilnya dua kali melempar. Penanda ini yang menjaganya.
  static bool _googleSiap = false;

  static Future<void> _siapkanGoogle() async {
    if (_googleSiap) return;
    // Tidak ada clientId yang ditulis di sini dengan sengaja:
    //  - iOS membacanya dari CLIENT_ID di GoogleService-Info.plist;
    //  - Android membaca default_web_client_id yang dihasilkan plugin
    //    google-services dari google-services.json.
    // Menyalinnya ke kode hanya menciptakan sumber kebenaran kedua yang
    // diam-diam basi ketika berkas konfigurasi diperbarui.
    await GoogleSignIn.instance.initialize();
    _googleSiap = true;
  }

  /// Masuk dengan akun Google, lalu tukar id token Google itu menjadi sesi
  /// Firebase Auth — sesi yang sama persis dengan hasil login email/sandi,
  /// sehingga sisa aplikasi tidak perlu tahu lewat mana penggunanya masuk.
  ///
  /// Mengembalikan false tanpa pesan bila pengguna membatalkan sendiri.
  static Future<bool> loginWithGoogle() async {
    lastError = '';

    if (!FirebaseService.ready) {
      lastError = 'Login Google butuh Firebase aktif. '
          '${FirebaseService.lastError ?? ''}'.trim();
      return false;
    }

    try {
      if (kIsWeb) {
        // Di web, authenticate() tidak didukung: Google mensyaratkan tombol
        // yang dirender SDK-nya sendiri. signInWithPopup milik Firebase
        // menempuh alur yang sama tanpa paket tambahan.
        await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
        isLoggedIn.value = true;
        return true;
      }

      await _siapkanGoogle();
      final akun = await GoogleSignIn.instance.authenticate();
      final idToken = akun.authentication.idToken;

      if (idToken == null) {
        // Nyaris selalu Android tanpa default_web_client_id: google-services.json
        // belum memuat OAuth client bertipe 3 (web).
        lastError = 'Google tidak mengirim id token. Unduh ulang '
            'google-services.json setelah provider Google diaktifkan dan '
            'SHA-1 didaftarkan di Firebase Console.';
        return false;
      }

      await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
      isLoggedIn.value = true;
      return true;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return false; // Dibatalkan pengguna: bukan kegagalan, jangan diteriaki.
      }
      lastError = switch (e.code) {
        GoogleSignInExceptionCode.clientConfigurationError =>
          'Konfigurasi Google Sign-In belum cocok. Di Android biasanya SHA-1 '
              'sidik jari penanda tangan belum terdaftar di Firebase Console.',
        GoogleSignInExceptionCode.providerConfigurationError =>
          'Provider Google belum aktif di Firebase Console '
              '(Authentication → Sign-in method → Google).',
        GoogleSignInExceptionCode.uiUnavailable =>
          'Layar pemilih akun Google tidak bisa dibuka di perangkat ini.',
        _ => 'Login Google gagal: ${e.code.name} ${e.description ?? ''}'.trim(),
      };
      return false;
    } on FirebaseAuthException catch (e) {
      if (_tolakanAppCheck('${e.code} ${e.message}')) {
        lastError = _pesanAppCheck;
        return false;
      }
      lastError = switch (e.code) {
        'account-exists-with-different-credential' =>
          'Email ini sudah terdaftar lewat cara masuk lain.',
        'network-request-failed' =>
          'Tidak ada koneksi. Login Google butuh internet.',
        _ => 'Login Google gagal: ${e.code}',
      };
      return false;
    } catch (e) {
      lastError =
          _tolakanAppCheck('$e') ? _pesanAppCheck : 'Login Google gagal: $e';
      return false;
    }
  }

  /// App Check yang di-*enforce* menolak permintaan Authentication sebelum
  /// kredensial sempat diperiksa. Gejalanya menyamar sebagai "sandi salah",
  /// jadi kasus ini dinamai sendiri agar tidak salah didiagnosis lagi.
  static const String _pesanAppCheck =
      'Ditolak Firebase App Check, bukan karena sandi salah. Matikan '
      'enforcement App Check untuk Authentication di Firebase Console, atau '
      'pasang paket firebase_app_check di aplikasi.';

  static bool _tolakanAppCheck(String teks) =>
      teks.toLowerCase().contains('app check');

  static Future<void> logout() async {
    if (FirebaseService.ready) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (e) {
        debugPrint('Gagal sign out Firebase: $e');
      }
    }
    // Tanpa ini, Google tetap memegang sesinya dan login berikutnya langsung
    // memakai akun lama tanpa menampilkan pemilih akun.
    if (!kIsWeb && _googleSiap) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (e) {
        debugPrint('Gagal sign out Google: $e');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loginPrefKey, false);
    isLoggedIn.value = false;
  }
}
