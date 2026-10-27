import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../models/vault_entry.dart';
import '../services/vault_service.dart';
import '../shared/shared_file_download.dart';
import '../viewer/memory_media_server.dart';

class MusicScreen extends StatefulWidget {
  const MusicScreen({required this.vault, super.key});

  final VaultService vault;

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  Player? _player;
  MemoryMediaServer? _mediaServer;
  Uint8List? _currentBytes;
  String? _error;
  String? _currentId;
  bool _loading = false;
  bool _shuffle = false;

  List<VaultEntry> get _tracks =>
      widget.vault.entries.where((entry) => entry.category == 'Audios').toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  @override
  void dispose() {
    _player?.dispose();
    _mediaServer?.close();
    super.dispose();
  }

  Future<void> _addMusic() async {
    try {
      await widget.vault.importFiles(category: 'Audios');
    } catch (error) {
      if (mounted) _showMessage('Could not add music: $error');
    }
  }

  Future<void> _play(VaultEntry track) async {
    setState(() {
      _loading = true;
      _error = null;
      _currentId = track.id;
    });
    MemoryMediaServer? nextServer;
    try {
      final bytes = await widget.vault.readFile(track);
      nextServer = MemoryMediaServer();
      final uri = await nextServer.start(bytes, track.extension);
      final player = _player ??= Player();
      await player.open(Media(uri.toString()), play: true);
      final previousServer = _mediaServer;
      _mediaServer = nextServer;
      _currentBytes = bytes;
      nextServer = null;
      await previousServer?.close();
    } catch (error) {
      await nextServer?.close();
      if (mounted) {
        setState(() {
          _error = 'Could not play ${track.name}: $error';
          _currentId = null;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _playAdjacent(int direction) async {
    final tracks = _tracks;
    if (tracks.isEmpty) return;
    final currentIndex = tracks.indexWhere((track) => track.id == _currentId);
    final nextIndex = _shuffle && tracks.length > 1
        ? (currentIndex +
                  1 +
                  (DateTime.now().microsecond % (tracks.length - 1))) %
              tracks.length
        : (currentIndex < 0 ? 0 : (currentIndex + direction) % tracks.length);
    await _play(tracks[nextIndex < 0 ? nextIndex + tracks.length : nextIndex]);
  }

  Future<void> _download(VaultEntry track, {Uint8List? bytes}) async {
    try {
      final content = bytes ?? await widget.vault.readFile(track);
      final location = await saveSharedFile(track.name, content);
      if (mounted) _showMessage('Downloaded ${track.name} to $location');
    } catch (error) {
      if (mounted) _showMessage('Download failed: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _tracks;
    final currentIndex = tracks.indexWhere((track) => track.id == _currentId);
    final currentTrack = currentIndex < 0 ? null : tracks[currentIndex];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Music'),
        actions: [
          IconButton(
            tooltip: 'Add music',
            onPressed: _addMusic,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: tracks.isEmpty
          ? _emptyState()
          : LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 760;
                final playlist = _playlist(tracks);
                if (!wide) {
                  return Column(
                    children: [
                      Expanded(child: playlist),
                      _playerPanel(currentTrack, currentIndex, tracks.length),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(flex: 3, child: playlist),
                    SizedBox(
                      width: 360,
                      child: _playerPanel(
                        currentTrack,
                        currentIndex,
                        tracks.length,
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.library_music_outlined, size: 72),
          const SizedBox(height: 16),
          Text(
            'Your music library is empty',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text('Add MP3 files to listen to them here.'),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _addMusic,
            icon: const Icon(Icons.add),
            label: const Text('Add music'),
          ),
        ],
      ),
    ),
  );

  Widget _playlist(List<VaultEntry> tracks) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Text(
          'Your library  ·  ${tracks.length} ${tracks.length == 1 ? 'track' : 'tracks'}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: tracks.length,
          itemBuilder: (context, index) {
            final track = tracks[index];
            final selected = track.id == _currentId;
            return ListTile(
              selected: selected,
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  selected ? Icons.graphic_eq : Icons.music_note,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              title: Text(
                track.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(_formatSize(track.size)),
              onTap: () => _play(track),
              trailing: IconButton(
                tooltip: 'Download ${track.name}',
                onPressed: () => _download(track),
                icon: const Icon(Icons.download_outlined),
              ),
            );
          },
        ),
      ),
    ],
  );

  Widget _playerPanel(
    VaultEntry? currentTrack,
    int currentIndex,
    int trackCount,
  ) {
    final player = _player;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      margin: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 190,
            height: 190,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.tertiary,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Icon(
              Icons.music_note,
              size: 96,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            currentTrack?.name ?? 'Choose a song',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(currentTrack == null ? 'Secure Vault library' : 'Your music'),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          if (player != null)
            StreamBuilder<Duration>(
              stream: player.stream.duration,
              initialData: Duration.zero,
              builder: (context, durationSnapshot) {
                final duration = durationSnapshot.data ?? Duration.zero;
                return StreamBuilder<Duration>(
                  stream: player.stream.position,
                  initialData: Duration.zero,
                  builder: (context, positionSnapshot) {
                    final position = positionSnapshot.data ?? Duration.zero;
                    final max = duration.inMilliseconds.toDouble();
                    return Column(
                      children: [
                        Slider(
                          value: max == 0
                              ? 0
                              : position.inMilliseconds.toDouble().clamp(
                                  0,
                                  max,
                                ),
                          max: max <= 0 ? 1 : max,
                          onChanged: duration == Duration.zero
                              ? null
                              : (value) => player.seek(
                                  Duration(milliseconds: value.round()),
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatDuration(position)),
                              Text(_formatDuration(duration)),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            )
          else
            const SizedBox(height: 56),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: _shuffle ? 'Turn shuffle off' : 'Turn shuffle on',
                onPressed: trackCount > 1
                    ? () => setState(() => _shuffle = !_shuffle)
                    : null,
                icon: Icon(
                  Icons.shuffle,
                  color: _shuffle
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
              IconButton(
                tooltip: 'Previous track',
                onPressed: trackCount == 0 ? null : () => _playAdjacent(-1),
                icon: const Icon(Icons.skip_previous),
                iconSize: 36,
              ),
              const SizedBox(width: 8),
              if (_loading)
                const SizedBox(
                  width: 56,
                  height: 56,
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                StreamBuilder<bool>(
                  stream: player?.stream.playing,
                  initialData: false,
                  builder: (context, snapshot) {
                    final playing = snapshot.data ?? false;
                    return IconButton.filled(
                      tooltip: playing ? 'Pause' : 'Play',
                      onPressed: player == null
                          ? null
                          : () => playing ? player.pause() : player.play(),
                      iconSize: 36,
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    );
                  },
                ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Next track',
                onPressed: trackCount == 0 ? null : () => _playAdjacent(1),
                icon: const Icon(Icons.skip_next),
                iconSize: 36,
              ),
              IconButton(
                tooltip: 'Download current track',
                onPressed: currentTrack == null
                    ? null
                    : () => _download(currentTrack, bytes: _currentBytes),
                icon: const Icon(Icons.download_outlined),
              ),
            ],
          ),
          if (currentTrack != null) Text('${currentIndex + 1} of $trackCount'),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString();
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatSize(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
