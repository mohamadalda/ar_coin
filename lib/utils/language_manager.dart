import 'package:flutter/material.dart';
import 'package:translator/translator.dart';
import '../models/hero_model.dart';

class LanguageManager {
  static final ValueNotifier<String> currentLanguage = ValueNotifier<String>('id');

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

  static final GoogleTranslator _translator = GoogleTranslator();

  /// Mengubah bahasa, menerjemahkan data hero secara on-the-fly jika belum ada, lalu menyimpan hasilnya
  static Future<void> changeLanguage(String targetLangCode, BuildContext context) async {
    if (targetLangCode == currentLanguage.value) return;

    // Tampilkan indikator loading global
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFD01B98)),
      ),
    );

    try {
      bool anyTranslated = false;

      // Iterasi ke semua hero
      for (var hero in mockHeroes) {
        // Terjemahkan nama jika belum ada (gunakan base 'id')
        if (!hero.name.containsKey(targetLangCode) && hero.name['id'] != null) {
          final t = await _translator.translate(hero.name['id']!, from: 'id', to: targetLangCode);
          hero.name[targetLangCode] = t.text;
          anyTranslated = true;
        }

        // Terjemahkan koin jika belum ada
        if (!hero.coin.containsKey(targetLangCode) && hero.coin['id'] != null) {
          final t = await _translator.translate(hero.coin['id']!, from: 'id', to: targetLangCode);
          hero.coin[targetLangCode] = t.text;
          anyTranslated = true;
        }

        // Terjemahkan deskripsi jika belum ada
        if (!hero.description.containsKey(targetLangCode) && hero.description['id'] != null) {
          final t = await _translator.translate(hero.description['id']!, from: 'id', to: targetLangCode);
          hero.description[targetLangCode] = t.text;
          anyTranslated = true;
        }
      }

      // Jika ada data baru yang diterjemahkan, simpan ke lokal agar selanjutnya instan
      if (anyTranslated) {
        await saveHeroes();
      }

      // Tutup dialog loading
      if (context.mounted) {
        Navigator.pop(context);
      }

      // Update state
      currentLanguage.value = targetLangCode;
    } catch (e) {
      debugPrint('Translation error: $e');
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal menerjemahkan teks. Pastikan ada koneksi internet.')),
        );
      }
    }
  }
}
