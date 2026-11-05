import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/hero_model.dart';
import '../models/test_record.dart';
import '../platform/web_download.dart';
import 'scanner_screen.dart';

/// Halaman pengujian akurasi pengenalan.
///
/// Alurnya sengaja memakai kebenaran acuan: pengguna memilih dulu objek apa
/// yang akan diuji, baru memindai. Tanpa acuan itu, aplikasi hanya bisa
/// melaporkan "sesuatu terdeteksi" dan tidak pernah bisa menghitung akurasi.
class TestScreen extends StatefulWidget {
  const TestScreen({super.key});

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  List<TestRecord> _records = [];
  bool _loading = true;

  static const _bg = Color(0xFF0F172A);
  static const _card = Color(0xFF1E293B);
  static const _purple = Color(0xFF6A0DAD);
  static const _pink = Color(0xFFD01B98);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await loadTestRecords();
    if (!mounted) return;
    setState(() {
      _records = r;
      _loading = false;
    });
  }

  Future<void> _startTest() async {
    final candidates = mockHeroes.where((h) => h.label.isNotEmpty).toList();
    if (candidates.isEmpty) {
      _toast('Belum ada hero yang punya Label Model untuk diuji.');
      return;
    }

    final expected = await showDialog<HeroModel>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: _card,
        title: const Text('Objek yang diuji',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        children: [
          for (final h in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, h),
              child: Text('${h.getName('id')}  ·  ${h.label}',
                  style: const TextStyle(color: Colors.white70)),
            ),
        ],
      ),
    );
    if (expected == null || !mounted) return;

    final result = await Navigator.push<TestRecord>(
      context,
      MaterialPageRoute(
          builder: (_) => ARScannerScreen(testExpected: expected)),
    );
    if (result == null || !mounted) return;

    final updated = [..._records, result];
    setState(() => _records = updated);
    await saveTestRecords(updated);
    if (!mounted) return;
    _toast(result.isCorrect
        ? 'Benar · ${result.durationMs} ms'
        : (result.isMiss
            ? 'Tidak terdeteksi dalam 15 detik'
            : 'Salah · terdeteksi ${result.detectedName}'));
  }

  Future<void> _exportCsv() async {
    final csv = TestSummary(_records).toCsv();

    // Di web yang dibutuhkan bukan "bagikan" melainkan "simpan": berkasnya
    // dipakai untuk lampiran KTI. getTemporaryDirectory() juga akan melempar
    // di sana, jadi jalur di bawah memang tidak bisa dipakai.
    if (kIsWeb) {
      final ok = downloadTextFile(
          'hasil_pengujian_imago.csv', csv, 'text/csv;charset=utf-8');
      if (!ok) {
        await Clipboard.setData(ClipboardData(text: csv));
        if (mounted) _toast('Unduhan gagal, CSV disalin ke clipboard.');
      } else if (mounted) {
        _toast('CSV diunduh.');
      }
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/hasil_pengujian_imago.csv');
      await file.writeAsString(csv);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        subject: 'Hasil Pengujian IMAGO',
      ));
    } catch (e) {
      // Berbagi berkas bisa gagal (mis. tidak ada aplikasi tujuan). Salinan
      // teks tetap menyelamatkan datanya supaya hasil uji tidak hilang.
      await Clipboard.setData(ClipboardData(text: csv));
      if (mounted) _toast('Ekspor gagal, CSV disalin ke clipboard.');
    }
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Hapus semua hasil?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
            'Seluruh catatan pengujian akan dihapus dan tidak bisa dikembalikan.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal', style: TextStyle(color: Colors.grey))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _records = []);
    await saveTestRecords([]);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: _card));
  }

  @override
  Widget build(BuildContext context) {
    final s = TestSummary(_records);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Pengujian'),
        backgroundColor: _purple,
        actions: [
          IconButton(
            tooltip: 'Ekspor CSV',
            icon: const Icon(Icons.ios_share),
            onPressed: _records.isEmpty ? null : _exportCsv,
          ),
          IconButton(
            tooltip: 'Salin ringkasan',
            icon: const Icon(Icons.copy_all),
            onPressed: _records.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(
                        ClipboardData(text: s.toCsv()));
                    if (mounted) _toast('Disalin ke clipboard.');
                  },
          ),
          IconButton(
            tooltip: 'Hapus semua',
            icon: const Icon(Icons.delete_sweep),
            onPressed: _records.isEmpty ? null : _clearAll,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _pink,
        onPressed: _startTest,
        icon: const Icon(Icons.play_arrow, color: Colors.white),
        label: const Text('Mulai Uji', style: TextStyle(color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _purple))
          : _records.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Belum ada data uji.\n\nTekan "Mulai Uji", pilih objek yang '
                      'akan diuji, lalu arahkan kamera ke objek itu.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, height: 1.5),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                  children: [
                    _summaryCard(s),
                    const SizedBox(height: 12),
                    _perClassCard(s),
                    const SizedBox(height: 12),
                    _confusionCard(s),
                    const SizedBox(height: 12),
                    _recordsCard(),
                  ],
                ),
    );
  }

  Widget _shell(String title, Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      );

  Widget _row(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(color: Colors.white60, fontSize: 13)),
            Text(v,
                style: TextStyle(
                    color: color ?? Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _summaryCard(TestSummary s) => _shell('Ringkasan', Column(
        children: [
          _row('Total percobaan', '${s.total}'),
          _row('Benar', '${s.correct}', color: Colors.greenAccent),
          _row('Salah kenal', '${s.wrong}', color: Colors.orangeAccent),
          _row('Tidak terdeteksi', '${s.missed}', color: Colors.redAccent),
          const Divider(color: Colors.white12),
          _row('Akurasi', '${(s.accuracy * 100).toStringAsFixed(1)}%',
              color: _pink),
          _row('Rata-rata waktu deteksi',
              '${s.avgDurationMs.toStringAsFixed(0)} ms'),
          _row('Rata-rata confidence',
              '${(s.avgConfidence * 100).toStringAsFixed(1)}%'),
        ],
      ));

  Widget _perClassCard(TestSummary s) => _shell(
        'Per kelas',
        Table(
          columnWidths: const {0: FlexColumnWidth(2)},
          children: [
            _tr(['Label', 'Presisi', 'Recall', 'F1'], header: true),
            for (final l in s.labels)
              _tr([
                l,
                '${(s.precision(l) * 100).toStringAsFixed(0)}%',
                '${(s.recall(l) * 100).toStringAsFixed(0)}%',
                '${(s.f1(l) * 100).toStringAsFixed(0)}%',
              ]),
          ],
        ),
      );

  Widget _confusionCard(TestSummary s) {
    final labels = s.labels;
    final m = s.confusion;
    return _shell(
      'Confusion matrix',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Baris = seharusnya, kolom = hasil deteksi',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const FixedColumnWidth(86),
              children: [
                _tr(['', ...labels, '(tidak)'], header: true),
                for (final rowLabel in labels)
                  _tr([
                    rowLabel,
                    ...labels.map(
                        (c) => '${m[rowLabel]?[c] ?? 0}'),
                    '${m[rowLabel]?['-'] ?? 0}',
                  ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TableRow _tr(List<String> cells, {bool header = false}) => TableRow(
        children: [
          for (final c in cells)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
              child: Text(
                c,
                style: TextStyle(
                  color: header ? Colors.white54 : Colors.white,
                  fontSize: 12,
                  fontWeight: header ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
        ],
      );

  Widget _recordsCard() => _shell(
        'Rincian (${_records.length})',
        Column(
          children: [
            for (var i = _records.length - 1; i >= 0; i--)
              _recordTile(i, _records[i]),
          ],
        ),
      );

  Widget _recordTile(int i, TestRecord r) {
    final color = r.isCorrect
        ? Colors.greenAccent
        : (r.isMiss ? Colors.redAccent : Colors.orangeAccent);
    final label = r.isCorrect ? 'benar' : (r.isMiss ? 'tidak' : 'salah');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
              width: 26,
              child: Text('${i + 1}',
                  style:
                      const TextStyle(color: Colors.white38, fontSize: 12))),
          Expanded(
            child: Text(
              r.isMiss
                  ? '${r.expectedLabel} → (tidak terdeteksi)'
                  : '${r.expectedLabel} → ${r.detectedLabel}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('${r.durationMs} ms',
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(label,
                style: TextStyle(color: color, fontSize: 10)),
          ),
        ],
      ),
    );
  }
}
