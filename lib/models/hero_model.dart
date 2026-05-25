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

Future<void> loadHeroes() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedData = prefs.getString(_kHeroesPrefsKey);

    if (savedData != null) {
      final List<dynamic> data = json.decode(savedData);
      mockHeroes = data.map((json) => HeroModel.fromJson(json)).toList();
      debugPrint('Loaded heroes from SharedPreferences');
    } else {
      final String response = await rootBundle.loadString('assets/heroes.json');
      final List<dynamic> data = json.decode(response);
      mockHeroes = data.map((json) => HeroModel.fromJson(json)).toList();
      debugPrint('Loaded heroes from assets/heroes.json');
    }
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
