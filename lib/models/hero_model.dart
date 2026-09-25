import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HeroModel {
  final Map<String, String> name;
  final Map<String, String> coin;
  final String image;
  final String audio; // Path ke file audio asset
  /// Path aset model 3D (.glb), relatif terhadap root project.
  /// Kosong berarti hero ini tidak punya model 3D.
  final String model;

  /// Apa yang ditampilkan saat hero terdeteksi: 'panel' (kartu keterangan saja)
  /// atau 'both' (model 3D muncul dulu, lalu kartu keterangan menyusul).
  /// Jatuh kembali ke 'panel' bila hero ini tidak punya model 3D.
  final String displayMode;

  static const String displayPanel = 'panel';
  static const String displayBoth = 'both';

  /// Mode yang benar-benar dipakai, sudah memperhitungkan ketersediaan model.
  String get effectiveDisplayMode =>
      (displayMode == displayBoth && model.isNotEmpty)
          ? displayBoth
          : displayPanel;
  final Map<String, String> description;
  final List<String> keywords;
  final String label;

  HeroModel({
    required this.name,
    required this.coin,
    required this.image,
    required this.description,
    this.audio = '',
    this.model = '',
    this.displayMode = displayPanel,
    this.keywords = const [],
    this.label = '',
  });

  factory HeroModel.fromJson(Map<String, dynamic> json) {
    return HeroModel(
      name: Map<String, String>.from(json['name'] ?? {}),
      coin: Map<String, String>.from(json['coin'] ?? {}),
      image: json['image'] ?? '',
      audio: json['audio'] ?? '',
      model: json['model'] ?? '',
      // 'model' adalah nilai dari versi sebelumnya yang menyembunyikan panel.
      // Dipetakan ke 'both' supaya data lama tidak kehilangan model 3D-nya.
      displayMode: json['displayMode'] == 'model'
          ? displayBoth
          : (json['displayMode'] ?? displayPanel),
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
      'model': model,
      'displayMode': displayMode,
      'description': description,
      'keywords': keywords,
      'label': label,
    };
  }

  HeroModel copyWith({String? model, String? displayMode}) => HeroModel(
        name: name,
        coin: coin,
        image: image,
        audio: audio,
        model: model ?? this.model,
        displayMode: displayMode ?? this.displayMode,
        description: description,
        keywords: keywords,
        label: label,
      );

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

    // Field `model` tidak punya kolom di halaman Admin, jadi assets adalah
    // satu-satunya sumbernya. Tanpa penyelarasan ini, hero yang sudah lebih
    // dulu ada di SharedPreferences — misalnya Barong yang dibuat manual —
    // akan selamanya kehilangan model 3D-nya, karena penyemaian di atas
    // melewati kunci yang sudah terdaftar.
    var modelsSynced = 0;
    final assetModels = {
      for (final h in assetHeroes)
        if (_heroKey(h).isNotEmpty && h.model.isNotEmpty) _heroKey(h): h.model
    };
    for (var i = 0; i < mockHeroes.length; i++) {
      final fromAsset = assetModels[_heroKey(mockHeroes[i])];
      if (fromAsset != null && mockHeroes[i].model != fromAsset) {
        mockHeroes[i] = mockHeroes[i].copyWith(model: fromAsset);
        modelsSynced++;
      }
    }

    if (newlySeeded.isNotEmpty || modelsSynced > 0) {
      if (newlySeeded.isNotEmpty) {
        await prefs.setStringList(
            _kSeededKeysPrefsKey, [...seeded, ...newlySeeded]);
        debugPrint('Seeded new heroes from assets: $newlySeeded');
      }
      await saveHeroes();
      if (modelsSynced > 0) {
        debugPrint('Synced 3D model path for $modelsSynced hero(es)');
      }
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
