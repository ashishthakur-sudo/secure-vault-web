import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class SharedFile {
  const SharedFile({
    required this.id,
    required this.name,
    required this.contentType,
    required this.size,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String contentType;
  final int size;
  final DateTime createdAt;

  String get extension {
    final separator = name.lastIndexOf('.');
    return separator < 0 ? '' : name.substring(separator + 1).toLowerCase();
  }

  String? get previewCategory {
    if (const {
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'bmp',
    }.contains(extension)) {
      return 'Images';
    }
    if (extension == 'pdf') return 'PDFs';
    if (const {'mp4', 'mkv'}.contains(extension)) return 'Videos';
    if (const {'mp3', 'wav'}.contains(extension)) return 'Audios';
    if (const {'txt', 'md', 'csv', 'json', 'xml', 'log'}.contains(extension)) {
      return 'Text';
    }
    return null;
  }

  factory SharedFile.fromJson(Map<String, dynamic> json) => SharedFile(
    id: json['id'] as String,
    name: json['name'] as String,
    contentType: json['contentType'] as String,
    size: json['size'] as int,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

class SharedFolderService {
  SharedFolderService({FlutterSecureStorage? storage, http.Client? client})
    : _storage = storage ?? const FlutterSecureStorage(),
      _client = client ?? http.Client();

  static const _urlKey = 'secure_vault.shared.supabase_url';
  static const _anonKey = 'secure_vault.shared.supabase_anon_key';
  static const _configurationVersionKey =
      'secure_vault.shared.configuration_version';
  static const _configurationVersion = '1';
  static const defaultProjectUrl = 'https://uxepshadypusifhvvwsf.supabase.co';
  static const defaultPublishableKey =
      'sb_publishable_JWNuaBqV-K2gq191GHDj1g_p_BMU3QI';

  final FlutterSecureStorage _storage;
  final http.Client _client;

  Future<String?> get projectUrl => _storage.read(key: _urlKey);
  Future<String?> get publishableKey => _storage.read(key: _anonKey);

  Future<void> configureDefaults() async {
    if (await _storage.read(key: _configurationVersionKey) !=
        _configurationVersion) {
      await _storage.write(key: _urlKey, value: defaultProjectUrl);
      await _storage.write(key: _anonKey, value: defaultPublishableKey);
      await _storage.write(
        key: _configurationVersionKey,
        value: _configurationVersion,
      );
      return;
    }
    if (await _storage.read(key: _urlKey) == null) {
      await _storage.write(key: _urlKey, value: defaultProjectUrl);
    }
    if (await _storage.read(key: _anonKey) == null) {
      await _storage.write(key: _anonKey, value: defaultPublishableKey);
    }
  }

  Future<bool> get isConfigured async {
    await configureDefaults();
    return await _storage.read(key: _urlKey) != null &&
        await _storage.read(key: _anonKey) != null;
  }

  Future<void> configure(String projectUrl, String anonKey) async {
    final uri = Uri.tryParse(projectUrl.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        !uri.host.endsWith('.supabase.co')) {
      throw const FormatException('Enter your Supabase HTTPS project URL.');
    }
    if (anonKey.trim().isEmpty) {
      throw const FormatException('Enter your Supabase publishable anon key.');
    }
    await _storage.write(key: _urlKey, value: uri.origin);
    await _storage.write(key: _anonKey, value: anonKey.trim());
  }

  Future<List<SharedFile>> listFiles(String pin) async {
    final response = await _request({'action': 'list', 'pin': pin});
    final files = response['files'];
    if (files is! List) {
      throw const FormatException(
        'The shared folder returned an invalid file list.',
      );
    }
    return files
        .map((item) => SharedFile.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> uploadFile(String pin, String name, Uint8List bytes) async {
    if (bytes.length > 4 * 1024 * 1024) {
      throw const FormatException('Shared uploads are limited to 4 MB.');
    }
    await _request({
      'action': 'upload',
      'pin': pin,
      'name': name,
      'contentBase64': base64Encode(bytes),
    });
  }

  Future<Uint8List> downloadFile(String pin, String id) async {
    final response = await _request({
      'action': 'download',
      'pin': pin,
      'id': id,
    });
    final content = response['contentBase64'];
    if (content is! String) {
      throw const FormatException('The shared file download was invalid.');
    }
    return base64Decode(content);
  }

  Future<void> verifyAdminResetKey(String adminKey) async {
    await _request({'action': 'admin-verify', 'adminKey': adminKey});
  }

  Future<void> resetSharedPin(String adminKey, String newPin) async {
    if (!RegExp(r'^\d{4}$').hasMatch(newPin)) {
      throw const FormatException(
        'Enter a new 4-digit shared-folder password.',
      );
    }
    await _request({
      'action': 'admin-set-pin',
      'adminKey': adminKey,
      'newPin': newPin,
    });
  }

  Future<Map<String, dynamic>> _request(Map<String, Object> body) async {
    final projectUrl = await _storage.read(key: _urlKey);
    final anonKey = await _storage.read(key: _anonKey);
    if (projectUrl == null || anonKey == null) {
      throw StateError(
        'Shared folder is not configured with a Supabase project.',
      );
    }
    late final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$projectUrl/functions/v1/shared-vault'),
        headers: {
          'content-type': 'application/json',
          'apikey': anonKey,
          'authorization': 'Bearer $anonKey',
        },
        body: jsonEncode(body),
      );
    } on http.ClientException {
      throw StateError(
        'Could not reach the Supabase shared-vault function. The function may '
        'not be deployed, or the project URL may be incorrect. Apply the '
        'database migration and deploy the function to the same project. '
        'See the Shared folder setup in README.md.',
      );
    }
    if (response.statusCode == 404) {
      throw StateError(
        'Supabase could not find the shared-vault function. Deploy it with '
        '`supabase functions deploy shared-vault --no-verify-jwt`.',
      );
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw StateError(
        'Supabase rejected this request. Check that the public key belongs '
        'to this project and deploy the function with JWT verification disabled.',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw FormatException(
        'Supabase returned an invalid response (HTTP ${response.statusCode}). '
        'Check that the shared-vault Edge Function is deployed.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'The shared folder returned an invalid response.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        decoded['error'] as String? ?? 'Shared folder request failed.',
      );
    }
    return decoded;
  }

  void dispose() => _client.close();
}
