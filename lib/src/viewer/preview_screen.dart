import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pdfx/pdfx.dart';

import '../models/vault_entry.dart';
import 'memory_media_server.dart';

class PreviewScreen extends StatefulWidget {
  const PreviewScreen({
    required this.entry,
    required this.bytes,
    this.onDownload,
    super.key,
  });

  final VaultEntry entry;
  final Uint8List bytes;
  final VoidCallback? onDownload;

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  PdfController? _pdfController;
  Player? _player;
  VideoController? _videoController;
  MemoryMediaServer? _mediaServer;
  String? _error;

  bool get _isPdf => widget.entry.extension == 'pdf';
  bool get _isImage => widget.entry.category == 'Images';
  bool get _isVideo => widget.entry.category == 'Videos';

  @override
  void initState() {
    super.initState();
    if (_isPdf) {
      _pdfController = PdfController(
        document: PdfDocument.openData(widget.bytes),
      );
    } else if (!_isImage) {
      _initializeMedia();
    }
  }

  Future<void> _initializeMedia() async {
    final server = MemoryMediaServer();
    try {
      final uri = await server.start(widget.bytes, widget.entry.extension);
      final player = Player();
      _mediaServer = server;
      _player = player;
      if (_isVideo) _videoController = VideoController(player);
      await player.open(Media(uri.toString()), play: true);
      if (mounted) setState(() {});
    } catch (error) {
      await server.close();
      if (mounted) setState(() => _error = 'Playback failed: $error');
    }
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    _player?.dispose();
    _mediaServer?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry.name),
        actions: [
          if (widget.onDownload != null)
            IconButton(
              tooltip: 'Download file',
              onPressed: widget.onDownload,
              icon: const Icon(Icons.download_outlined),
            ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!),
              ),
            )
          : _isImage
          ? Center(
              child: InteractiveViewer(
                child: Image.memory(widget.bytes, fit: BoxFit.contain),
              ),
            )
          : _isPdf
          ? PdfView(
              controller: _pdfController!,
              builders: PdfViewBuilders<DefaultBuilderOptions>(
                options: const DefaultBuilderOptions(),
                documentLoaderBuilder: (_) =>
                    const Center(child: CircularProgressIndicator()),
                pageLoaderBuilder: (_) =>
                    const Center(child: CircularProgressIndicator()),
                errorBuilder: (context, error) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not display this PDF. Check your '
                      'connection and try again, or download the file.\n\n'
                      '$error',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            )
          : _isVideo
          ? _videoController == null
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Video(controller: _videoController!),
                    ),
                  )
          : _audioPlayer(),
    );
  }

  Widget _audioPlayer() {
    final player = _player;
    if (player == null) return const Center(child: CircularProgressIndicator());
    return Center(
      child: StreamBuilder<bool>(
        stream: player.stream.playing,
        initialData: false,
        builder: (context, snapshot) {
          final playing = snapshot.data ?? false;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.audio_file_outlined, size: 88),
              const SizedBox(height: 16),
              Text(widget.entry.name),
              IconButton.filled(
                iconSize: 40,
                onPressed: () => playing ? player.pause() : player.play(),
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              ),
            ],
          );
        },
      ),
    );
  }
}
