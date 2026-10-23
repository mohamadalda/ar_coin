/// Mengunduh berkas di web.
///
/// share_plus punya implementasi web, tapi ia memakai Web Share API yang di
/// banyak browser desktop tidak tersedia untuk berkas — dan yang dibutuhkan
/// di sini memang bukan "bagikan", melainkan "simpan hasil uji". Blob plus
/// anchor download adalah jalan yang pasti ada di semua browser.
library;

import 'web_download_stub.dart'
    if (dart.library.js_interop) 'web_download_web.dart' as impl;

/// Menyimpan [content] sebagai berkas bernama [filename].
/// Mengembalikan false bila tidak didukung di platform ini.
bool downloadTextFile(String filename, String content, String mimeType) =>
    impl.downloadTextFile(filename, content, mimeType);
