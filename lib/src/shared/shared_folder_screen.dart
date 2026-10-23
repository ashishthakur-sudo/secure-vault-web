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
  String? _adminResetKey;
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
                _pinController.clear();
              }),
              icon: const Icon(Icons.lock_outline),
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
          : _fileList(),
      floatingActionButton: _unlocked
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
                trailing: TextButton.icon(
                  onPressed: _busy ? null : () => _download(file),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Download'),
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
