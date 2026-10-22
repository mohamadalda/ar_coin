import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Satu percobaan pengujian: objek apa yang SEHARUSNYA dikenali, apa yang
/// benar-benar dikenali sistem, seberapa yakin, dan berapa lama.
///
/// Label kosong pada [detectedLabel] berarti sistem tidak mengenali apa pun
/// sampai batas waktu habis — ini kasus yang berbeda dari salah mengenali, dan
/// dibedakan karena keduanya punya arti berbeda pada evaluasi model.
class TestRecord {
  final String expectedLabel;
  final String expectedName;
  final String detectedLabel;
  final String detectedName;
  final double confidence;
  final int durationMs;
  final DateTime at;

  const TestRecord({
    required this.expectedLabel,
    required this.expectedName,
    required this.detectedLabel,
    required this.detectedName,
    required this.confidence,
    required this.durationMs,
    required this.at,
  });

  bool get isCorrect =>
      detectedLabel.isNotEmpty && detectedLabel == expectedLabel;
  bool get isMiss => detectedLabel.isEmpty;
  bool get isWrong => detectedLabel.isNotEmpty && detectedLabel != expectedLabel;

  Map<String, dynamic> toJson() => {
        'expectedLabel': expectedLabel,
        'expectedName': expectedName,
        'detectedLabel': detectedLabel,
        'detectedName': detectedName,
        'confidence': confidence,
        'durationMs': durationMs,
        'at': at.toIso8601String(),
      };

  factory TestRecord.fromJson(Map<String, dynamic> j) => TestRecord(
        expectedLabel: j['expectedLabel'] ?? '',
        expectedName: j['expectedName'] ?? '',
        detectedLabel: j['detectedLabel'] ?? '',
        detectedName: j['detectedName'] ?? '',
        confidence: (j['confidence'] ?? 0).toDouble(),
        durationMs: (j['durationMs'] ?? 0) as int,
        at: DateTime.tryParse(j['at'] ?? '') ?? DateTime(2000),
      );
}

const String _kTestPrefsKey = 'test_records';

Future<List<TestRecord>> loadTestRecords() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kTestPrefsKey);
    if (raw == null) return [];
    final List<dynamic> data = json.decode(raw);
    return data.map((e) => TestRecord.fromJson(e)).toList();
  } catch (e) {
    debugPrint('Gagal membaca hasil pengujian: $e');
    return [];
  }
}

Future<void> saveTestRecords(List<TestRecord> records) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kTestPrefsKey, json.encode(records.map((e) => e.toJson()).toList()));
  } catch (e) {
    debugPrint('Gagal menyimpan hasil pengujian: $e');
  }
}

/// Ringkasan metrik dari sekumpulan percobaan.
class TestSummary {
  final List<TestRecord> records;
  TestSummary(this.records);

  int get total => records.length;
  int get correct => records.where((r) => r.isCorrect).length;
  int get wrong => records.where((r) => r.isWrong).length;
  int get missed => records.where((r) => r.isMiss).length;

  /// Akurasi keseluruhan: percobaan benar dibagi seluruh percobaan.
  double get accuracy => total == 0 ? 0 : correct / total;

  /// Rata-rata waktu deteksi, HANYA dari percobaan yang berhasil mengenali.
  /// Percobaan yang gagal selalu berakhir di batas waktu, jadi memasukkannya
  /// akan menggeser rata-rata ke angka yang tidak berarti.
  double get avgDurationMs {
    final ok = records.where((r) => !r.isMiss).toList();
    if (ok.isEmpty) return 0;
    return ok.map((r) => r.durationMs).reduce((a, b) => a + b) / ok.length;
  }

  double get avgConfidence {
    final ok = records.where((r) => !r.isMiss).toList();
    if (ok.isEmpty) return 0;
    return ok.map((r) => r.confidence).reduce((a, b) => a + b) / ok.length;
  }

  /// Semua label yang terlibat, baik sebagai acuan maupun sebagai hasil.
  List<String> get labels {
    final set = <String>{};
    for (final r in records) {
      if (r.expectedLabel.isNotEmpty) set.add(r.expectedLabel);
      if (r.detectedLabel.isNotEmpty) set.add(r.detectedLabel);
    }
    final list = set.toList()..sort();
    return list;
  }

  /// matrix[acuan][hasil] = jumlah. Kunci hasil '-' berarti tidak terdeteksi.
  Map<String, Map<String, int>> get confusion {
    final m = <String, Map<String, int>>{};
    for (final r in records) {
      final row = m.putIfAbsent(r.expectedLabel, () => <String, int>{});
      final key = r.detectedLabel.isEmpty ? '-' : r.detectedLabel;
      row[key] = (row[key] ?? 0) + 1;
    }
    return m;
  }

  /// Presisi: dari semua yang DITEBAK sebagai label ini, berapa yang benar.
  double precision(String label) {
    final predicted = records.where((r) => r.detectedLabel == label).length;
    if (predicted == 0) return 0;
    final hit = records.where((r) => r.detectedLabel == label && r.isCorrect).length;
    return hit / predicted;
  }

  /// Recall: dari semua yang SEHARUSNYA label ini, berapa yang tertangkap.
  double recall(String label) {
    final actual = records.where((r) => r.expectedLabel == label).length;
    if (actual == 0) return 0;
    final hit = records.where((r) => r.expectedLabel == label && r.isCorrect).length;
    return hit / actual;
  }

  double f1(String label) {
    final p = precision(label);
    final rc = recall(label);
    if (p + rc == 0) return 0;
    return 2 * p * rc / (p + rc);
  }

  String toCsv() {
    final b = StringBuffer();
    b.writeln('no,waktu,label_acuan,nama_acuan,label_terdeteksi,'
        'nama_terdeteksi,confidence,durasi_ms,hasil');
    for (var i = 0; i < records.length; i++) {
      final r = records[i];
      final hasil = r.isCorrect ? 'benar' : (r.isMiss ? 'tidak_terdeteksi' : 'salah');
      b.writeln('${i + 1},${r.at.toIso8601String()},${r.expectedLabel},'
          '"${r.expectedName}",${r.detectedLabel},"${r.detectedName}",'
          '${r.confidence.toStringAsFixed(4)},${r.durationMs},$hasil');
    }
    b.writeln();
    b.writeln('ringkasan');
    b.writeln('total,$total');
    b.writeln('benar,$correct');
    b.writeln('salah,$wrong');
    b.writeln('tidak_terdeteksi,$missed');
    b.writeln('akurasi,${(accuracy * 100).toStringAsFixed(2)}%');
    b.writeln('rata_rata_durasi_ms,${avgDurationMs.toStringAsFixed(0)}');
    b.writeln('rata_rata_confidence,${avgConfidence.toStringAsFixed(4)}');
    b.writeln();
    b.writeln('per_kelas,presisi,recall,f1');
    for (final l in labels) {
      b.writeln('$l,${(precision(l) * 100).toStringAsFixed(2)}%,'
          '${(recall(l) * 100).toStringAsFixed(2)}%,'
          '${(f1(l) * 100).toStringAsFixed(2)}%');
    }
    return b.toString();
  }
}
