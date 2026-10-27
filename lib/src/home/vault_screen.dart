import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/vault_entry.dart';
import '../music/music_screen.dart';
import '../shared/shared_file_download.dart';
import '../shared/shared_folder_screen.dart';
import '../services/vault_service.dart';
import '../viewer/preview_screen.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({
    required this.vault,
    required this.decoyMode,
    required this.onLock,
    required this.onSignOut,
    super.key,
  });

  final VaultService vault;
  final bool decoyMode;
  final Future<void> Function() onLock;
  final Future<void> Function() onSignOut;

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  String _selectedCategory = 'Images';
  bool _busy = false;

  Future<void> _importFiles() async {
    setState(() => _busy = true);
    try {
      await widget.vault.importFiles();
    } catch (error) {
      if (mounted) _showMessage('Import failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openEntry(VaultEntry entry) async {
    try {
      final bytes = await widget.vault.readFile(entry);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PreviewScreen(
            entry: entry,
            bytes: bytes,
            onDownload: () => _downloadEntry(entry, bytes),
          ),
        ),
      );
    } catch (error) {
      if (mounted) _showMessage('Could not open ${entry.name}: $error');
    }
  }

  Future<void> _downloadEntry(VaultEntry entry, Uint8List bytes) async {
    try {
      final location = await saveSharedFile(entry.name, bytes);
      if (mounted) _showMessage('Downloaded ${entry.name} to $location');
    } catch (error) {
      if (mounted) _showMessage('Download failed: $error');
    }
  }

  Future<void> _deleteEntry(VaultEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete encrypted file?'),
        content: Text('Remove "${entry.name}" from this vault?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.vault.deleteEntry(entry);
    } catch (error) {
      if (mounted) _showMessage('Delete failed: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Secure Vault'),
        actions: [
          TextButton.icon(
            onPressed: widget.decoyMode
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MusicScreen(vault: widget.vault),
                    ),
                  ),
            icon: const Icon(Icons.music_note),
            label: const Text('Music'),
          ),
          TextButton.icon(
            onPressed: _busy || widget.decoyMode
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SharedFolderScreen(),
                    ),
                  ),
            icon: const Icon(Icons.folder_shared_outlined),
            label: const Text('Shared'),
          ),
          if (!widget.decoyMode)
            IconButton(
              tooltip: 'Import files',
              onPressed: _busy ? null : _importFiles,
              icon: const Icon(Icons.add),
            ),
          IconButton(
            tooltip: 'Lock vault',
            onPressed: widget.onLock,
            icon: const Icon(Icons.lock),
          ),
          IconButton(
            tooltip: 'Sign out of cloud account',
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: VaultService.categories.keys
                  .map(
                    (category) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      child: ChoiceChip(
                        label: Text(category == 'Audios' ? 'Music' : category),
                        selected: category == _selectedCategory,
                        onSelected: (_) =>
                            setState(() => _selectedCategory = category),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: widget.decoyMode
                ? const Center(child: Text('No files'))
                : AnimatedBuilder(
                    animation: widget.vault,
                    builder: (context, _) {
                      final entries =
                          widget.vault.entries
                              .where(
                                (entry) => entry.category == _selectedCategory,
                              )
                              .toList()
                            ..sort(
                              (a, b) => b.createdAt.compareTo(a.createdAt),
                            );
                      if (entries.isEmpty) {
                        return const Center(
                          child: Text('No files in this folder'),
                        );
                      }
                      return ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return ListTile(
                            leading: Icon(_iconFor(entry.category)),
                            title: Text(
                              entry.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(_formatBytes(entry.size)),
                            onTap: () => _openEntry(entry),
                            trailing: IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _deleteEntry(entry),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String category) => switch (category) {
    'Images' => Icons.image_outlined,
    'PDFs' => Icons.picture_as_pdf_outlined,
    'Videos' => Icons.movie_outlined,
    _ => Icons.audiotrack_outlined,
  };

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
