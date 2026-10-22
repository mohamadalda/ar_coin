import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
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
        lastError = 'Login gagal: $e';
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

  static Future<void> logout() async {
    if (FirebaseService.ready) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (e) {
        debugPrint('Gagal sign out Firebase: $e');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loginPrefKey, false);
    isLoggedIn.value = false;
  }
}
