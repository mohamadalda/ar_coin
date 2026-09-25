import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class FileHelper {
  /// Mengecek apakah string path merujuk ke file lokal di storage perangkat
  /// (bukan dari bundle assets aplikasi).
  static bool isLocalFile(String path) {
    if (path.isEmpty) return false;
    // Biasanya path asset kita mulai dengan 'assets/'
    // Sedangkan path absolut lokal dimulai dengan '/' (Android/iOS/Mac/Linux) atau 'C:\' dll (Windows)
    return p.isAbsolute(path);
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
      final savedImage = await sourceFile.copy('${uploadsDir.path}/$fileName');
      return savedImage.path;
    } catch (e) {
      debugPrint('Error saving file locally: $e');
      return null;
    }
  }

  /// Menghapus file lokal jika ada. Jangan hapus jika itu file asset.
  static Future<void> deleteLocalFile(String path) async {
    if (isLocalFile(path)) {
      try {
        final file = File(path);
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
