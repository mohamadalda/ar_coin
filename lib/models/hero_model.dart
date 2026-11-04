import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/auth_service.dart';
import '../utils/firebase_service.dart';

class HeroModel {
  final Map<String, String> name;
  final Map<String, String> coin;
  final String image;
  final String audio; // Path ke file audio asset
  /// Path aset model 3D (.glb), relatif terhadap root project.
  /// Kosong berarti hero ini tidak punya model 3D.
  final String model;

  /// Gambar rincian koin (diagram fitur keamanan), ditampilkan menggantikan
  /// aset 3D saat tombol nama ditekan. Kosong berarti hero ini tidak punya.
  final String infoImage;

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
    this.infoImage = '',
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
      infoImage: json['infoImage'] ?? '',
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
      'infoImage': infoImage,
      'displayMode': displayMode,
      'description': description,
      'keywords': keywords,
      'label': label,
    };
  }

  /// Bentuk untuk Firestore: TANPA jalur berkas media.
  ///
  /// `model`, `infoImage`, dan berkas lain ikut ter-bundle di aplikasi dan
  /// selalu ditimpa dari assets saat dimuat. Menuliskannya ke Firestore hanya
  /// menghasilkan field yang tidak pernah dibaca — dan tampak "kosong" di
  /// console seolah ada yang rusak, padahal tidak.
  Map<String, dynamic> toFirestoreJson() {
    final j = toJson();
    j.remove('model');
    j.remove('infoImage');
    return j;
  }

  HeroModel copyWith({String? model, String? displayMode, String? infoImage}) =>
      HeroModel(
        name: name,
        coin: coin,
        image: image,
        audio: audio,
        model: model ?? this.model,
        displayMode: displayMode ?? this.displayMode,
        infoImage: infoImage ?? this.infoImage,
        description: description,
        keywords: keywords,
        label: label,
      );

  // Helper untuk mengambil teks berdasarkan bahasa. Bahasa tanpa terjemahan
  // resmi jatuh ke Inggris dulu (lebih mungkin dipahami pengunjung asing),
  // baru ke Indonesia sebagai bahasa sumber.
  static String _pick(Map<String, String> m, String lang) {
    for (final k in [lang, 'en', 'id']) {
      final v = m[k];
      if (v != null && v.trim().isNotEmpty) return v;
    }
    return '';
  }

  String getName(String lang) => _pick(name, lang);
  String getCoin(String lang) => _pick(coin, lang);
  String getDescription(String lang) => _pick(description, lang);
}

List<HeroModel> mockHeroes = [];

const String _kHeroesPrefsKey = 'heroes_data';

/// Kunci hero bawaan yang sudah pernah disemai ke SharedPreferences.
/// Dicatat agar hero yang sengaja dihapus pengguna tidak muncul lagi tiap
/// aplikasi dibuka, sementara entri baru di assets tetap bisa masuk.
const String _kSeededKeysPrefsKey = 'heroes_seeded_keys';

/// Kunci identitas hero.
///
/// Memakai [HeroModel.label] lebih dulu, BUKAN nama. Dua hero boleh bernama
/// sama — misalnya dua varian koin Rangda yang hanya berbeda gambar rincian —
/// dan kalau namanya dipakai sebagai kunci, keduanya akan saling menimpa di
/// Firestore dan salah satunya tidak akan pernah disemai ke perangkat.
/// Nama hanya dipakai sebagai cadangan untuk hero tanpa label.
String _heroKey(HeroModel h) {
  final label = h.label.trim();
  if (label.isNotEmpty) return label;
  return h.name['id'] ?? '';
}

const String _kHeroesCollection = 'heroes';

/// Mengambil metadata hero dari Firestore.
///
/// Mengembalikan null bila Firebase tidak aktif atau koleksinya masih kosong —
/// keduanya BUKAN kesalahan, hanya berarti sumbernya belum ada dan pemanggil
/// harus memakai data lokal.
Future<List<HeroModel>?> _fetchHeroesFromFirestore() async {
  if (!FirebaseService.ready) return null;
  try {
    final snap = await FirebaseFirestore.instance
        .collection(_kHeroesCollection)
        .get()
        .timeout(const Duration(seconds: 8));
    if (snap.docs.isEmpty) return null;
    return snap.docs.map((d) => HeroModel.fromJson(d.data())).toList();
  } catch (e) {
    debugPrint('Gagal membaca hero dari Firestore: $e');
    return null;
  }
}

/// Penulisan ke Firestore hanya untuk sesi administrator.
///
/// Ini hanya penyaring di sisi aplikasi agar pengunjung biasa tidak pernah
/// mencoba menulis. Penegakan sebenarnya ada di `firestore.rules`, yang
/// menolak penulisan tanpa claim `admin` — temuan pentest IMAGO no. 2.
bool get _canWriteRemote => FirebaseService.ready && AuthService.isLoggedIn.value;

/// Id dokumen Firestore untuk sebuah hero.
String heroDocId(HeroModel h) => FirebaseService.docIdFor(_heroKey(h));

/// Menulis SATU hero ke Firestore (membuat atau menimpa dokumennya saja).
///
/// Sebelumnya setiap simpan menghapus seluruh koleksi lalu menulis ulang dari
/// salinan di perangkat, sehingga dokumen yang tidak ada di salinan itu ikut
/// terhapus dan dua penyimpanan bersamaan saling menimpa.
Future<bool> upsertHeroInFirestore(HeroModel hero) async {
  if (!_canWriteRemote) return false;
  try {
    await FirebaseFirestore.instance
        .collection(_kHeroesCollection)
        .doc(heroDocId(hero))
        .set(hero.toFirestoreJson());
    debugPrint('Hero disimpan ke Firestore: ${heroDocId(hero)}');
    return true;
  } catch (e) {
    debugPrint('Gagal menulis hero ke Firestore: $e');
    return false;
  }
}

/// Menghapus SATU dokumen hero dari Firestore.
Future<bool> deleteHeroFromFirestore(String docId) async {
  if (!_canWriteRemote) return false;
  try {
    await FirebaseFirestore.instance
        .collection(_kHeroesCollection)
        .doc(docId)
        .delete();
    debugPrint('Hero dihapus dari Firestore: $docId');
    return true;
  } catch (e) {
    debugPrint('Gagal menghapus hero dari Firestore: $e');
    return false;
  }
}

/// Menyelaraskan berkas media dari assets ke daftar hero yang sedang aktif.
///
/// Model 3D dan gambar rincian sengaja TIDAK bisa diatur dari Admin maupun
/// Firestore — berkasnya ikut ter-bundle di aplikasi, jadi assets adalah
/// kebenarannya. Tanpa penyelarasan ini, data dari Firestore (yang hanya
/// membawa metadata) akan menghapus jalur berkas tersebut.
/// Nama yang dinormalkan untuk pencocokan: huruf kecil dan tanpa spasi ganda.
/// Pencocokan yang menuntut nama persis terlalu rapuh — hero yang dibuat
/// manual lewat Admin sering berbeda tipis ("rangda", "Rangda ") dan akibatnya
/// berkas media dari assets tidak pernah terpasang padanya.
String _matchKey(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

int _syncMediaFromAssets(List<HeroModel> assetHeroes) {
  var synced = 0;
  // Dicocokkan lewat nama DAN label. Label adalah kunci yang dipakai mesin
  // pengenal, sehingga lebih mungkin konsisten daripada nama yang bebas diketik.
  final assetModels = <String, String>{};
  final assetInfoImages = <String, String>{};
  for (final h in assetHeroes) {
    for (final k in [_matchKey(_heroKey(h)), _matchKey(h.label)]) {
      if (k.isEmpty) continue;
      if (h.model.isNotEmpty) assetModels.putIfAbsent(k, () => h.model);
      if (h.infoImage.isNotEmpty) {
        assetInfoImages.putIfAbsent(k, () => h.infoImage);
      }
    }
  }

  for (var i = 0; i < mockHeroes.length; i++) {
    final byName = _matchKey(_heroKey(mockHeroes[i]));
    final byLabel = _matchKey(mockHeroes[i].label);
    final model = assetModels[byName] ?? assetModels[byLabel];
    final info = assetInfoImages[byName] ?? assetInfoImages[byLabel];
    // Hanya MENGISI yang kosong, tidak menimpa. Sejak kedua field ini bisa
    // dipilih sendiri lewat Admin, menimpanya dari assets berarti pilihan
    // pengguna terhapus diam-diam setiap aplikasi dibuka.
    if (model != null && mockHeroes[i].model.isEmpty) {
      mockHeroes[i] = mockHeroes[i].copyWith(model: model);
      synced++;
    }
    if (info != null && mockHeroes[i].infoImage.isEmpty) {
      mockHeroes[i] = mockHeroes[i].copyWith(infoImage: info);
      synced++;
    }
  }
  return synced;
}

Future<void> loadHeroes() async {
  try {
    final prefs = await SharedPreferences.getInstance();

    // Hero bawaan aplikasi selalu dibaca. Sebelumnya file ini dilewati begitu
    // SharedPreferences terisi, sehingga hero yang ditambahkan pada rilis
    // berikutnya tidak akan pernah muncul di perangkat yang sudah dipakai.
    final String response = await rootBundle.loadString('assets/heroes.json');
    final List<dynamic> assetData = json.decode(response);
    final assetHeroes = assetData.map((j) => HeroModel.fromJson(j)).toList();

    // Firestore lebih diutamakan bila aktif dan berisi. Hasilnya disimpan ke
    // SharedPreferences sebagai cadangan, supaya aplikasi tetap menampilkan
    // data terbaru saat berikutnya dibuka tanpa jaringan.
    final remote = await _fetchHeroesFromFirestore();
    if (remote != null && remote.isNotEmpty) {
      mockHeroes = remote;
      _syncMediaFromAssets(assetHeroes);
      await prefs.setString(_kHeroesPrefsKey,
          json.encode(mockHeroes.map((h) => h.toJson()).toList()));
      debugPrint('Loaded ${mockHeroes.length} heroes dari Firestore');
      return;
    }

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
    final modelsSynced = _syncMediaFromAssets(assetHeroes);

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

/// Menyimpan daftar hero ke penyimpanan LOKAL perangkat saja.
///
/// Tidak menulis ke Firestore. Perubahan oleh admin dikirim per dokumen lewat
/// [upsertHeroInFirestore] / [deleteHeroFromFirestore].
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
