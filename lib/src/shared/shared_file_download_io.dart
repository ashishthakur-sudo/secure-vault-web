import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> saveSharedFile(String name, Uint8List bytes) async {
  final documents = await getApplicationDocumentsDirectory();
  final directory = Directory(p.join(documents.path, 'SecureVaultShared'));
  await directory.create(recursive: true);
  final file = File(p.join(directory.path, p.basename(name)));
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
