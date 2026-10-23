import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool downloadTextFile(String filename, String content, String mimeType) {
  try {
    final blob = web.Blob(
      [content.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final url = web.URL.createObjectURL(blob);
    final a = web.document.createElement('a') as web.HTMLAnchorElement;
    a.href = url;
    a.download = filename;
    // Anchor tidak perlu masuk ke dokumen untuk bisa diklik secara terprogram,
    // dan tidak memasukkannya berarti tidak ada yang perlu dibersihkan.
    a.click();
    // Dilepas setelah klik sempat diproses; melepasnya langsung membatalkan
    // unduhan di sebagian browser.
    web.window.setTimeout(
      (() => web.URL.revokeObjectURL(url)).toJS,
      10000.toJS,
    );
    return true;
  } catch (_) {
    return false;
  }
}
