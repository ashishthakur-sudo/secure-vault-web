import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class MemoryMediaServer {
  String? _objectUrl;

  Future<Uri> start(Uint8List bytes, String extension) async {
    if (_objectUrl != null) throw StateError('Memory media server is already running.');
    final mimeType = switch (extension) {
      'mp4' => 'video/mp4',
      'mkv' => 'video/x-matroska',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      _ => 'application/octet-stream',
    };
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    _objectUrl = web.URL.createObjectURL(blob);
    return Uri.parse(_objectUrl!);
  }

  Future<void> close() async {
    final url = _objectUrl;
    _objectUrl = null;
    if (url != null) web.URL.revokeObjectURL(url);
  }
}
