import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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
  List<SharedFile> _files = [];
  bool _configured = false;
  bool _unlocked = false;
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
    super.dispose();
  }

  Future<void> _loadConfiguration() async {
    final configured = await _service.isConfigured;
    if (mounted) setState(() => _configured = configured);
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
      final files = await _service.listFiles(pin);
      if (mounted) {
        setState(() {
          _files = files;
          _unlocked = true;
        });
      }
    });
  }

  Future<void> _upload() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    final file = files.first;
    final bytes = await file.readAsBytes();
    await _run(() async {
      await _service.uploadFile(_pinController.text, file.name, bytes);
      final files = await _service.listFiles(_pinController.text);
      if (mounted) setState(() => _files = files);
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

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
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
                _pinController.clear();
              }),
              icon: const Icon(Icons.lock_outline),
            ),
          if (_unlocked)
            IconButton(
              tooltip: 'Upload file',
              onPressed: _busy ? null : _upload,
              icon: const Icon(Icons.upload_file),
            ),
          if (!_configured)
            IconButton(
              tooltip: 'Configure cloud sharing',
              onPressed: _showConfiguration,
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
          : _fileList(),
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
              'Cloud sharing needs a Supabase project. Configure the project URL and public anon key to continue.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _showConfiguration,
              child: const Text('Configure shared folder'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Do not enter a service-role key here. A 4-digit password is weak; access must be rate-limited by the server.',
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
            if (_error != null) Text(_error!),
            FilledButton(onPressed: _unlock, child: const Text('Open Shared')),
          ],
        ),
      ),
    ),
  );

  Widget _fileList() {
    if (_error != null) return Center(child: Text(_error!));
    if (_files.isEmpty) {
      return const Center(
        child: Text('No files in Shared yet. Upload a file to share it.'),
      );
    }
    return ListView.builder(
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        return ListTile(
          leading: const Icon(Icons.insert_drive_file_outlined),
          title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${_formatBytes(file.size)} • ${file.createdAt.toLocal()}',
          ),
          trailing: IconButton(
            tooltip: 'Download ${file.name}',
            onPressed: () => _download(file),
            icon: const Icon(Icons.download_outlined),
          ),
        );
      },
    );
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
