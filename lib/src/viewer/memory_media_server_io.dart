import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class MemoryMediaServer {
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _requests;

  Future<Uri> start(Uint8List bytes, String extension) async {
    if (_server != null) throw StateError('Memory media server is already running.');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final random = Random.secure();
    final token = List<int>.generate(16, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    _server = server;
    _requests = server.listen((request) => _respond(request, bytes, extension, token));
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: server.port,
      path: '/$token/media.$extension',
    );
  }

  Future<void> _respond(
    HttpRequest request,
    Uint8List bytes,
    String extension,
    String token,
  ) async {
    if (request.uri.pathSegments.isEmpty || request.uri.pathSegments.first != token) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    final response = request.response;
    response.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.contentTypeHeader, _contentType(extension))
      ..set(HttpHeaders.cacheControlHeader, 'no-store');

    final range = request.headers.value(HttpHeaders.rangeHeader);
    var start = 0;
    var end = bytes.length - 1;
    if (range != null) {
      final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
      if (match == null || (match[1]!.isEmpty && match[2]!.isEmpty)) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */${bytes.length}');
        await response.close();
        return;
      }
      if (match[1]!.isEmpty) {
        final suffixLength = int.parse(match[2]!);
        start = (bytes.length - suffixLength).clamp(0, bytes.length);
      } else {
        start = int.parse(match[1]!);
        if (match[2]!.isNotEmpty) end = int.parse(match[2]!);
      }
      if (start >= bytes.length || end < start) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */${bytes.length}');
        await response.close();
        return;
      }
      end = end.clamp(0, bytes.length - 1);
      response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/${bytes.length}');
    }

    response.contentLength = end - start + 1;
    if (request.method == 'GET') response.add(bytes.sublist(start, end + 1));
    await response.close();
  }

  String _contentType(String extension) => switch (extension) {
        'mp4' => 'video/mp4',
        'mkv' => 'video/x-matroska',
        'mp3' => 'audio/mpeg',
        'wav' => 'audio/wav',
        _ => 'application/octet-stream',
      };

  Future<void> close() async {
    await _requests?.cancel();
    _requests = null;
    await _server?.close(force: true);
    _server = null;
  }
}
