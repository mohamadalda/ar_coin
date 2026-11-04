import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_service.dart';

/// Status sesi administrator.
///
/// Keputusan "apakah ini admin" HANYA diambil dari token Firebase Auth yang
/// ditandatangani Google, lewat custom claim `admin: true`. Claim yang sama
/// ditegakkan oleh Firestore Security Rules (lihat `firestore.rules`), jadi
/// tampilan di aplikasi dan izin di server selalu sejalan.
///
/// Tidak ada kredensial di kode, tidak ada login cadangan, dan tidak ada
/// penanda di penyimpanan lokal. Bila Firebase tidak tersedia, akses admin
/// DITOLAK (fail-closed) — temuan pentest IMAGO no. 1 dan 3.
class AuthService {
  /// True hanya bila ada sesi Firebase yang sah DAN tokennya membawa claim
  /// `admin: true`. Dipakai untuk menampilkan menu admin.
  static final ValueNotifier<bool> isLoggedIn = ValueNotifier<bool>(false);

  /// Penanda lama dari versi yang memakai login lokal. Tidak lagi dibaca;
  /// hanya dibersihkan agar tidak tertinggal di perangkat pengguna.
  static const String _legacyLoginPrefKey = 'is_admin_logged_in';

  /// Pesan kesalahan terakhir, agar layar login bisa menjelaskan sebabnya
  /// alih-alih sekadar bilang "gagal".
  static String lastError = '';

  static Future<void> init() async {
    await _clearLegacyFlag();

    if (!FirebaseService.ready) {
      isLoggedIn.value = false;
      return;
    }

    // idTokenChanges juga terpicu saat token diperbarui, sehingga pencabutan
    // claim admin ikut terbaca tanpa harus logout manual.
    FirebaseAuth.instance.idTokenChanges().listen((user) async {
      isLoggedIn.value = await _hasAdminClaim(user);
    });
    isLoggedIn.value = await _hasAdminClaim(FirebaseAuth.instance.currentUser);
  }

  static Future<bool> _hasAdminClaim(User? user,
      {bool forceRefresh = false}) async {
    if (user == null) return false;
    try {
      final token = await user.getIdTokenResult(forceRefresh);
      return token.claims?['admin'] == true;
    } catch (e) {
      debugPrint('Gagal membaca claim admin: $e');
      return false;
    }
  }

  static Future<bool> login(String email, String password) async {
    lastError = '';

    if (!FirebaseService.ready) {
      lastError = 'Login admin membutuhkan koneksi ke Firebase.';
      return false;
    }

    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      // Paksa ambil token baru supaya claim yang baru saja diberikan
      // langsung terbaca, bukan token lama dari cache.
      final isAdmin = await _hasAdminClaim(cred.user, forceRefresh: true);
      if (!isAdmin) {
        await FirebaseAuth.instance.signOut();
        isLoggedIn.value = false;
        lastError = 'Akun ini tidak memiliki hak administrator.';
        return false;
      }

      isLoggedIn.value = true;
      return true;
    } on FirebaseAuthException catch (e) {
      lastError = switch (e.code) {
        'invalid-email' => 'Format email tidak valid.',
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' =>
          'Email atau kata sandi salah.',
        'user-disabled' => 'Akun ini dinonaktifkan.',
        'network-request-failed' =>
          'Tidak ada koneksi. Login admin butuh internet.',
        'too-many-requests' => 'Terlalu banyak percobaan. Coba lagi nanti.',
        _ => 'Login gagal: ${e.code}',
      };
      return false;
    } catch (e) {
      lastError = 'Login gagal: $e';
      return false;
    }
  }

  static Future<void> logout() async {
    if (FirebaseService.ready) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (e) {
        debugPrint('Gagal sign out Firebase: $e');
      }
    }
    await _clearLegacyFlag();
    isLoggedIn.value = false;
  }

  static Future<void> _clearLegacyFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_legacyLoginPrefKey);
    } catch (_) {
      // Tidak kritis: penanda ini sudah tidak dibaca di mana pun.
    }
  }
}
