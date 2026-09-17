import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HeroModel {
  final Map<String, String> name;
  final Map<String, String> coin;
  final String image;
  final String audio; // Path ke file audio asset
  final Map<String, String> description;
  final List<String> keywords;
  final String label;

  HeroModel({
    required this.name,
    required this.coin,
    required this.image,
    required this.description,
    this.audio = '',
    this.keywords = const [],
    this.label = '',
  });

  factory HeroModel.fromJson(Map<String, dynamic> json) {
    return HeroModel(
      name: Map<String, String>.from(json['name'] ?? {}),
      coin: Map<String, String>.from(json['coin'] ?? {}),
      image: json['image'] ?? '',
      audio: json['audio'] ?? '',
      description: Map<String, String>.from(json['description'] ?? {}),
      keywords: List<String>.from(json['keywords'] ?? []),
      label: json['label'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'coin': coin,
      'image': image,
      'audio': audio,
      'description': description,
      'keywords': keywords,
      'label': label,
    };
  }

  // Helper untuk mengambil teks berdasarkan bahasa
  String getName(String lang) => name[lang] ?? name['id'] ?? '';
  String getCoin(String lang) => coin[lang] ?? coin['id'] ?? '';
  String getDescription(String lang) => description[lang] ?? description['id'] ?? '';
}

List<HeroModel> mockHeroes = [];

const String _kHeroesPrefsKey = 'heroes_data';

/// Kunci hero bawaan yang sudah pernah disemai ke SharedPreferences.
/// Dicatat agar hero yang sengaja dihapus pengguna tidak muncul lagi tiap
/// aplikasi dibuka, sementara entri baru di assets tetap bisa masuk.
const String _kSeededKeysPrefsKey = 'heroes_seeded_keys';

String _heroKey(HeroModel h) => h.name['id'] ?? '';

Future<void> loadHeroes() async {
  try {
    final prefs = await SharedPreferences.getInstance();

    // Hero bawaan aplikasi selalu dibaca. Sebelumnya file ini dilewati begitu
    // SharedPreferences terisi, sehingga hero yang ditambahkan pada rilis
    // berikutnya tidak akan pernah muncul di perangkat yang sudah dipakai.
    final String response = await rootBundle.loadString('assets/heroes.json');
    final List<dynamic> assetData = json.decode(response);
    final assetHeroes = assetData.map((j) => HeroModel.fromJson(j)).toList();

    final savedData = prefs.getString(_kHeroesPrefsKey);
    if (savedData == null) {
      mockHeroes = assetHeroes;
      await prefs.setStringList(
        _kSeededKeysPrefsKey,
        assetHeroes.map(_heroKey).where((k) => k.isNotEmpty).toList(),
      );
      debugPrint('Loaded ${mockHeroes.length} heroes from assets/heroes.json');
      return;
    }

    final List<dynamic> data = json.decode(savedData);
    mockHeroes = data.map((j) => HeroModel.fromJson(j)).toList();

    final seeded = prefs.getStringList(_kSeededKeysPrefsKey) ??
        mockHeroes.map(_heroKey).where((k) => k.isNotEmpty).toList();

    final newlySeeded = <String>[];
    for (final hero in assetHeroes) {
      final key = _heroKey(hero);
      if (key.isEmpty || seeded.contains(key)) continue;
      mockHeroes.add(hero);
      newlySeeded.add(key);
    }

    if (newlySeeded.isNotEmpty) {
      await prefs.setStringList(_kSeededKeysPrefsKey, [...seeded, ...newlySeeded]);
      await saveHeroes();
      debugPrint('Seeded new heroes from assets: $newlySeeded');
    }

    debugPrint('Loaded ${mockHeroes.length} heroes (SharedPreferences + assets)');
  } catch (e) {
    debugPrint('Failed to load heroes data: $e');
  }
}

Future<void> saveHeroes() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final String encodedData = json.encode(mockHeroes.map((h) => h.toJson()).toList());
    await prefs.setString(_kHeroesPrefsKey, encodedData);
    debugPrint('Saved heroes to SharedPreferences');
  } catch (e) {
    debugPrint('Failed to save heroes data: $e');
  }
}
