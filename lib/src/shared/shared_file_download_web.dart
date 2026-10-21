import 'dart:typed_data';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<String> saveSharedFile(String name, Uint8List bytes) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/octet-stream'),
  );
  final url = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  link.click();
  Future<void>.delayed(const Duration(seconds: 30), () {
    web.URL.revokeObjectURL(url);
  });
  return name;
}
