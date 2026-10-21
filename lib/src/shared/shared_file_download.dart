import 'dart:typed_data';

import 'shared_file_download_stub.dart'
    if (dart.library.io) 'shared_file_download_io.dart'
    if (dart.library.js_interop) 'shared_file_download_web.dart'
    as platform;

Future<String> saveSharedFile(String name, Uint8List bytes) =>
    platform.saveSharedFile(name, bytes);
