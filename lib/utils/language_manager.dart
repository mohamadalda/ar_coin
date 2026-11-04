import 'package:flutter/material.dart';

class LanguageManager {
  /// Bahasa tampilan saat aplikasi dibuka.
  ///
  /// 'id' tetap menjadi bahasa SUMBER data hero di heroes.json — terjemahan ke
  /// bahasa lain diturunkan darinya. Yang diubah di sini hanya bahasa yang
  /// ditampilkan lebih dulu kepada pengguna.
  static final ValueNotifier<String> currentLanguage = ValueNotifier<String>('en');

  static final List<Map<String, String>> supportedLanguages = [
    {'code': 'id', 'name': 'Indonesia'},
    {'code': 'en', 'name': 'English'},
    {'code': 'ja', 'name': '日本語 (Japanese)'},
    {'code': 'ko', 'name': '한국어 (Korean)'},
    {'code': 'ar', 'name': 'العربية (Arabic)'},
    {'code': 'es', 'name': 'Español (Spanish)'},
    {'code': 'zh-cn', 'name': '中文 (Chinese)'},
    {'code': 'ms', 'name': 'Melayu (Malay)'}, // Brunei, Malaysia, Singapore
    {'code': 'km', 'name': 'ខ្មែរ (Khmer)'}, // Kamboja
    {'code': 'lo', 'name': 'ລາວ (Lao)'}, // Laos
    {'code': 'my', 'name': 'မြန်မာ (Burmese)'}, // Myanmar
    {'code': 'th', 'name': 'ไทย (Thai)'}, // Thailand
    {'code': 'vi', 'name': 'Tiếng Việt (Vietnamese)'}, // Vietnam
    {'code': 'ta', 'name': 'தமிழ் (Tamil)'}, // Singapore
  ];

  /// Mengganti bahasa tampilan.
  ///
  /// Tidak ada lagi penerjemahan mesin on-the-fly: teks hero hanya berasal
  /// dari terjemahan resmi yang tersimpan di heroes.json / Firestore. Bahasa
  /// yang belum punya terjemahan memakai bahasa Inggris, lalu Indonesia
  /// (lihat [HeroModel.getName]). Perubahan bahasa juga TIDAK menulis apa pun
  /// ke Firestore — temuan pentest IMAGO no. 2 dan 11.
  ///
  /// [context] dipertahankan agar pemanggil yang ada tidak perlu berubah.
  static Future<void> changeLanguage(
      String targetLangCode, BuildContext context) async {
    if (targetLangCode == currentLanguage.value) return;
    currentLanguage.value = targetLangCode;
  }
}
