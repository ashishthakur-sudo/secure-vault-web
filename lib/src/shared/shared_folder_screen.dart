import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/vault_entry.dart';
import '../viewer/docx_text_extractor.dart';
import '../viewer/preview_screen.dart';
import 'shared_file_download.dart';
import 'shared_folder_service.dart';

class SharedFolderScreen extends StatefulWidget {
  const SharedFolderScreen({super.key});

  @override
  State<SharedFolderScreen> createState() => _SharedFolderScreenState();
}

class _SharedFolderScreenState extends State<SharedFolderScreen> {
  final _service = SharedFolderService();
  final _pinController = TextEditingController();
  final _urlController = TextEditingController();
  final _anonKeyController = TextEditingController();
  String? _adminResetKey;
  List<SharedFile> _files = [];
  List<SharedFile> _trashFiles = [];
  bool _configured = false;
  bool _unlocked = false;
  bool _trashOpen = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConfiguration();
  }

  @override
  void dispose() {
    _service.dispose();
    _pinController.dispose();
    _urlController.dispose();
    _anonKeyController.dispose();
    _adminResetKey = null;
    super.dispose();
  }

  Future<void> _loadConfiguration() async {
    final configured = await _service.isConfigured;
    final projectUrl = await _service.projectUrl;
    final publishableKey = await _service.publishableKey;
    if (!configured) return;
    if (mounted) {
      setState(() {
        _configured = true;
        _urlController.text = projectUrl ?? '';
        _anonKeyController.text = publishableKey ?? '';
      });
    }
  }

  Future<void> _configure() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.configure(_urlController.text, _anonKeyController.text);
      if (mounted) {
        setState(() {
          _configured = true;
          _busy = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _busy = false;
        });
      }
    }
  }

  Future<void> _unlock() async {
    final pin = _pinController.text;
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      setState(() => _error = 'Enter the 4-digit shared-folder password.');
      return;
    }
    await _run(() async {
      final results = await Future.wait([
        _service.listFiles(pin),
        _service.listTrashFiles(pin),
      ]);
      if (mounted) {
        setState(() {
          _files = results[0];
          _trashFiles = results[1];
          _unlocked = true;
          _trashOpen = false;
        });
      }
    });
  }

  Future<void> _upload() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Add files, images, or videos to Shared',
    );
    if (files.isEmpty) return;
    await _run(() async {
      for (final file in files) {
        final bytes = await file.readAsBytes();
        await _service.uploadFile(_pinController.text, file.name, bytes);
        final uploadedFiles = await _service.listFiles(_pinController.text);
        if (mounted) setState(() => _files = uploadedFiles);
      }
    });
  }

  Future<void> _openTrash() async {
    await _run(() async {
      final files = await _service.listTrashFiles(_pinController.text);
      if (mounted) {
        setState(() {
          _trashFiles = files;
          _trashOpen = true;
        });
      }
    });
  }

  Future<void> _showSharedFiles() async {
    setState(() => _trashOpen = false);
  }

  Future<void> _moveToTrash(SharedFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Move file to Trash?'),
        content: Text(
          '"${file.name}" will be removed from Shared. You can restore it from Trash.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Move to Trash'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await _service.moveToTrash(_pinController.text, file.id);
      final results = await Future.wait([
        _service.listFiles(_pinController.text),
        _service.listTrashFiles(_pinController.text),
      ]);
      if (mounted) {
        setState(() {
          _files = results[0];
          _trashFiles = results[1];
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('File moved to Trash.')));
      }
    });
  }

  Future<void> _restoreFromTrash(SharedFile file) async {
    await _run(() async {
      await _service.restoreFromTrash(_pinController.text, file.id);
      final results = await Future.wait([
        _service.listFiles(_pinController.text),
        _service.listTrashFiles(_pinController.text),
      ]);
      if (mounted) {
        setState(() {
          _files = results[0];
          _trashFiles = results[1];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File restored to Shared.')),
        );
      }
    });
  }

  Future<void> _download(SharedFile file) async {
    await _run(() async {
      final bytes = await _service.downloadFile(_pinController.text, file.id);
      final location = await saveSharedFile(file.name, bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded ${file.name} to $location')),
        );
      }
    });
  }

  Future<void> _view(SharedFile file) async {
    await _run(() async {
      if (!mounted) return;

      final category = file.previewCategory;
      if (category == null) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _SharedUnsupportedPreview(file: file),
          ),
        );
        return;
      }

      final bytes = await _service.downloadFile(_pinController.text, file.id);
      if (!mounted) return;
      if (category == 'DOCX') {
        final text = extractDocxText(bytes);
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _SharedDocxPreview(name: file.name, text: text),
          ),
        );
        return;
      }
      if (file.previewCategory == 'Text') {
        final text = utf8.decode(bytes, allowMalformed: true);
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _SharedTextPreview(name: file.name, text: text),
          ),
        );
        return;
      }

      final entry = VaultEntry(
        id: file.id,
        name: file.name,
        category: category,
        extension: file.extension,
        createdAt: file.createdAt,
        size: file.size,
      );
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PreviewScreen(entry: entry, bytes: bytes),
        ),
      );
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError
              ? error.message.toString()
              : error.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared'),
        actions: [
          if (_unlocked)
            IconButton(
              tooltip: 'Lock shared folder',
              onPressed: () => setState(() {
                _unlocked = false;
                _files = [];
                _trashFiles = [];
                _trashOpen = false;
                _pinController.clear();
              }),
              icon: const Icon(Icons.lock_outline),
            ),
          if (_unlocked)
            IconButton(
              tooltip: _trashOpen ? 'Back to shared files' : 'Open Trash',
              onPressed: _busy
                  ? null
                  : _trashOpen
                  ? _showSharedFiles
                  : _openTrash,
              icon: _trashOpen
                  ? const Icon(Icons.folder_shared_outlined)
                  : Badge(
                      isLabelVisible: _trashFiles.isNotEmpty,
                      label: Text('${_trashFiles.length}'),
                      child: const Icon(Icons.delete_outline),
                    ),
            ),
          IconButton(
            tooltip: _adminResetKey == null
                ? 'Admin sign in'
                : 'Reset shared-folder password',
            onPressed: _busy
                ? null
                : _adminResetKey == null
                ? _showAdminSignIn
                : _showAdminPinReset,
            icon: Icon(
              _adminResetKey == null
                  ? Icons.admin_panel_settings_outlined
                  : Icons.password_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Configure cloud sharing',
            onPressed: _busy ? null : _showConfiguration,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : !_configured
          ? _configurationPrompt()
          : !_unlocked
          ? _pinForm()
          : _trashOpen
          ? _trashList()
          : _fileList(),
      floatingActionButton: _unlocked && !_trashOpen
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _upload,
              icon: const Icon(Icons.add),
              label: const Text('Add files'),
            )
          : null,
    );
  }

  Widget _configurationPrompt() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Cloud sharing requires a deployed Supabase shared-vault Edge Function. Enter your project URL and public key here after the backend has been deployed.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _showConfiguration,
              child: const Text('Configure shared folder'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Entering these values alone does not create or deploy the backend. Follow the Shared folder setup in the project README. Never enter a service-role key here.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _pinForm() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_shared_outlined, size: 48),
            const SizedBox(height: 12),
            const Text('Enter the shared-folder 4-digit password'),
            const SizedBox(height: 16),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: const InputDecoration(labelText: '4-digit password'),
              onSubmitted: (_) => _unlock(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            FilledButton(
              onPressed: _busy ? null : _unlock,
              child: const Text('Open Shared'),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _showAdminSignIn() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final adminKey = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Admin sign in'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Admin reset key'),
            validator: (value) => value == null || value.isEmpty
                ? 'Enter the admin reset key.'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(dialogContext, controller.text);
            },
            child: const Text('Verify'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (adminKey == null || !mounted) return;
    await _run(() async {
      await _service.verifyAdminResetKey(adminKey);
      if (mounted) setState(() => _adminResetKey = adminKey);
    });
  }

  Future<void> _showAdminPinReset() async {
    final pinController = TextEditingController();
    final confirmationController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final adminKey = _adminResetKey;
    if (adminKey == null) return;

    final newPin = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset shared-folder password'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: pinController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New 4-digit password',
                ),
                validator: (value) =>
                    value == null || !RegExp(r'^\d{4}$').hasMatch(value)
                    ? 'Enter exactly 4 digits.'
                    : null,
              ),
              TextFormField(
                controller: confirmationController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                ),
                validator: (value) => value != pinController.text
                    ? 'Passwords do not match.'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(dialogContext, pinController.text);
            },
            child: const Text('Reset password'),
          ),
        ],
      ),
    );
    pinController.dispose();
    confirmationController.dispose();
    if (newPin == null || !mounted) return;
    await _run(() async {
      await _service.resetSharedPin(adminKey, newPin);
      _pinController.text = newPin;
      if (_unlocked) {
        final files = await _service.listFiles(newPin);
        if (mounted) setState(() => _files = files);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shared-folder password was reset.')),
        );
      }
    });
  }

  Widget _fileList() {
    if (_files.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_shared_outlined, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Add files, images, or videos to share them. Each upload can be up to 4 MB.',
                textAlign: TextAlign.center,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _upload,
                icon: const Icon(Icons.upload_file),
                label: const Text('Add files'),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        if (_error != null)
          MaterialBanner(
            content: Text(_error!),
            actions: [
              TextButton(
                onPressed: () => setState(() => _error = null),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _files.length,
            itemBuilder: (context, index) {
              final file = _files[index];
              return ListTile(
                leading: Icon(_iconForFile(file.name)),
                title: Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${_formatBytes(file.size)} • ${file.createdAt.toLocal()}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'View ${file.name}',
                      onPressed: _busy ? null : () => _view(file),
                      icon: const Icon(Icons.visibility_outlined),
                    ),
                    IconButton(
                      tooltip: 'Download ${file.name}',
                      onPressed: _busy ? null : () => _download(file),
                      icon: const Icon(Icons.download_outlined),
                    ),
                    IconButton(
                      tooltip: 'Move ${file.name} to Trash',
                      onPressed: _busy ? null : () => _moveToTrash(file),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _trashList() {
    if (_trashFiles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.delete_outline, size: 48),
              const SizedBox(height: 12),
              const Text('Trash is empty.'),
              const SizedBox(height: 8),
              const Text(
                'Files moved here can be restored to the Shared folder.',
                textAlign: TextAlign.center,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        if (_error != null)
          MaterialBanner(
            content: Text(_error!),
            actions: [
              TextButton(
                onPressed: () => setState(() => _error = null),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _trashFiles.length,
            itemBuilder: (context, index) {
              final file = _trashFiles[index];
              return ListTile(
                leading: Icon(_iconForFile(file.name)),
                title: Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${_formatBytes(file.size)} • ${file.createdAt.toLocal()}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'View ${file.name}',
                      onPressed: _busy ? null : () => _view(file),
                      icon: const Icon(Icons.visibility_outlined),
                    ),
                    IconButton(
                      tooltip: 'Restore ${file.name}',
                      onPressed: _busy ? null : () => _restoreFromTrash(file),
                      icon: const Icon(Icons.restore_outlined),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  IconData _iconForFile(String name) {
    final extension = name.split('.').last.toLowerCase();
    if (const {
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'bmp',
    }.contains(extension)) {
      return Icons.image_outlined;
    }
    if (const {'mp4', 'mkv', 'mov', 'avi', 'webm'}.contains(extension)) {
      return Icons.video_file_outlined;
    }
    if (const {'mp3', 'wav', 'm4a', 'aac', 'ogg'}.contains(extension)) {
      return Icons.audio_file_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Future<void> _showConfiguration() async {
    final formKey = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configure cloud sharing'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'The shared-vault Edge Function must already be deployed to this Supabase project. Saving a URL and public key alone is not enough.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Supabase project URL',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter the project URL.'
                    : null,
              ),
              TextFormField(
                controller: _anonKeyController,
                decoration: const InputDecoration(labelText: 'Public anon key'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter the public anon key.'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(context);
              await _configure();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _SharedTextPreview extends StatelessWidget {
  const _SharedTextPreview({required this.name, required this.text});

  static const _maxCharacters = 200000;

  final String name;
  final String text;

  @override
  Widget build(BuildContext context) {
    final truncated = text.length > _maxCharacters;
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Column(
        children: [
          if (truncated)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.all(12),
              child: const Text(
                'Preview limited to the first 200,000 characters.',
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                truncated ? text.substring(0, _maxCharacters) : text,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SharedUnsupportedPreview extends StatelessWidget {
  const _SharedUnsupportedPreview({required this.file});

  final SharedFile file;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(file.name)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file_outlined, size: 64),
              const SizedBox(height: 16),
              Text(file.name, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'Preview is not supported for .${file.extension} files. '
                'Use Download to open this file in a compatible app.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SharedDocxPreview extends StatelessWidget {
  const _SharedDocxPreview({required this.name, required this.text});

  final String name;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Text(
              'Text-only preview. Word formatting, images, and some layout '
              'details may not be preserved.',
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: SelectableText(text),
            ),
          ),
        ],
      ),
    );
  }
}
