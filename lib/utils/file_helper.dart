import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class FileHelper {
  /// Folder dokumen aplikasi, di-cache sekali supaya [resolve] bisa sinkron
  /// dan dipakai langsung di dalam build().
  static String? _docsDir;

  /// Prefix penanda berkas unggahan yang disimpan secara relatif.
  static const String _uploadsPrefix = 'uploads/';

  /// Wajib dipanggil sekali saat aplikasi start, sebelum data hero dibaca.
  static Future<void> init() async {
    _docsDir = (await getApplicationDocumentsDirectory()).path;
  }

  /// Mengecek apakah string path merujuk ke file lokal di storage perangkat
  /// (bukan dari bundle assets aplikasi).
  static bool isLocalFile(String path) {
    if (path.isEmpty) return false;
    // Berkas unggahan baru disimpan relatif ('uploads/...'). Path absolut
    // tetap dikenali demi data lama yang tersimpan sebelum perubahan ini.
    return path.startsWith(_uploadsPrefix) || p.isAbsolute(path);
  }

  /// Mengubah nilai tersimpan menjadi path yang benar-benar bisa dibuka.
  ///
  /// Di iOS, folder dokumen aplikasi mengandung UUID yang BERGANTI setiap kali
  /// aplikasi dipasang ulang. Menyimpan path absolut membuat seluruh berkas
  /// unggahan rusak setelah reinstall — karena itu yang disimpan hanya bagian
  /// relatifnya, lalu disambung di sini saat dibaca.
  static String resolve(String stored) {
    if (stored.startsWith(_uploadsPrefix) && _docsDir != null) {
      return p.join(_docsDir!, stored);
    }
    return stored;
  }

  /// Menyalin file ke Application Documents Directory agar permanen.
  /// prefix digunakan untuk membedakan antara image dan audio.
  static Future<String?> saveFileLocally(File sourceFile, String prefix) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      // Buat folder uploads jika belum ada
      final uploadsDir = Directory('${directory.path}/uploads');
      if (!await uploadsDir.exists()) {
        await uploadsDir.create(recursive: true);
      }

      final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${p.basename(sourceFile.path)}';
      await sourceFile.copy('${uploadsDir.path}/$fileName');
      // Yang dikembalikan relatif, bukan absolut — lihat [resolve].
      return '$_uploadsPrefix$fileName';
    } catch (e) {
      debugPrint('Error saving file locally: $e');
      return null;
    }
  }

  /// Menghapus file lokal jika ada. Jangan hapus jika itu file asset.
  static Future<void> deleteLocalFile(String path) async {
    if (isLocalFile(path)) {
      try {
        final file = File(resolve(path));
        if (await file.exists()) {
          await file.delete();
          debugPrint('Deleted local file: $path');
        }
      } catch (e) {
        debugPrint('Error deleting file: $e');
      }
    }
  }
}
