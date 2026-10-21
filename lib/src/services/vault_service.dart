import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../models/vault_entry.dart';
import 'vault_store.dart';

class VaultService extends ChangeNotifier {
  VaultService({VaultStore? store}) : _store = store ?? createVaultStore();

  static const categories = <String, List<String>>{
    'Images': ['jpg', 'jpeg', 'png', 'webp'],
    'PDFs': ['pdf'],
    'Videos': ['mp4', 'mkv'],
    'Audios': ['mp3', 'wav'],
  };
  static const _formatMagic = [83, 86, 76, 84, 1];
  static const _iterations = 210000;

  final VaultStore _store;
  Uint8List? _encryptionKey;
  Uint8List? _macKey;
  List<VaultEntry> _entries = [];

  List<VaultEntry> get entries => List.unmodifiable(_entries);
  bool get isUnlocked => _encryptionKey != null;

  Future<void> create(String password) async {
    final salt = _secureRandomBytes(16);
    await _store.create(salt);
    await _deriveKeys(password, salt);
    _entries = [];
  }

  Future<void> unlock(String password) async {
    final salt = await _store.readSalt();
    if (salt == null) {
      throw StateError('Vault key metadata is missing. The vault cannot be unlocked.');
    }
    await _deriveKeys(password, salt);
    try {
      _entries = await _readEntries();
    } catch (_) {
      await _store.close();
      _wipe(_encryptionKey);
      _wipe(_macKey);
      _encryptionKey = null;
      _macKey = null;
      rethrow;
    }
    notifyListeners();
  }

  Future<void> _deriveKeys(String password, List<int> salt) async {
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _iterations,
      bits: 512,
    );
    final secret = await algorithm.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final bytes = await secret.extractBytes();
    _encryptionKey = Uint8List.fromList(bytes.sublist(0, 32));
    _macKey = Uint8List.fromList(bytes.sublist(32, 64));
  }

  Future<void> importFiles() async {
    _requireUnlocked();
    final pickedFiles = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: categories.values.expand((items) => items).toList(),
    );

    for (final picked in pickedFiles) {
      final bytes = await picked.readAsBytes();
      final extension = p.extension(picked.name).replaceFirst('.', '').toLowerCase();
      final category = _categoryFor(extension);
      if (category == null) {
        throw FormatException('Unsupported file type: ${picked.name}');
      }
      final id = _newId();
      final encryptedFile = await _encrypt(bytes);
      final entry = VaultEntry(
        id: id,
        name: p.basename(picked.name),
        category: category,
        extension: extension,
        createdAt: DateTime.now().toUtc(),
        size: bytes.length,
      );
      final metadata = await _encrypt(utf8.encode(jsonEncode(entry.toJson())));
      await _store.writeEntry(id, category, encryptedFile, metadata);
      _entries = [..._entries, entry];
    }
    notifyListeners();
  }

  Future<Uint8List> readFile(VaultEntry entry) async {
    _requireUnlocked();
    final encryptedFile = await _store.readFile(entry.id, entry.category);
    if (encryptedFile == null) {
      throw StateError('The encrypted file for ${entry.name} is missing.');
    }
    return _decrypt(encryptedFile);
  }

  Future<void> deleteEntry(VaultEntry entry) async {
    _requireUnlocked();
    await _store.deleteEntry(entry.id, entry.category);
    _entries = _entries.where((candidate) => candidate.id != entry.id).toList();
    notifyListeners();
  }

  Future<void> lock() async {
    await _store.close();
    _wipe(_encryptionKey);
    _wipe(_macKey);
    _encryptionKey = null;
    _macKey = null;
    _entries = [];
    notifyListeners();
  }

  Future<List<VaultEntry>> _readEntries() async {
    var rows = await _store.readEntries();
    final legacyIndex = await _store.readLegacyIndex();
    if (rows.isEmpty && legacyIndex != null) {
      final decoded = jsonDecode(
        utf8.decode(await _decrypt(legacyIndex)),
      );
      if (decoded is! List) {
        throw const FormatException('Legacy vault index is invalid.');
      }
      final entries = decoded
          .map((item) => VaultEntry.fromJson(item as Map<String, dynamic>))
          .toList();
      final migratedRows = <StoredVaultRow>[];
      for (final entry in entries) {
        migratedRows.add(
          StoredVaultRow(
            entry.id,
            Uint8List.fromList(
              await _encrypt(utf8.encode(jsonEncode(entry.toJson()))),
            ),
          ),
        );
      }
      await _store.writeMigratedEntries(migratedRows);
      await _store.clearLegacyIndex();
      rows = await _store.readEntries();
    }
    return Future.wait(
      rows.map((row) async {
        final metadata = await _decrypt(row.payload);
        return VaultEntry.fromJson(
          jsonDecode(utf8.decode(metadata)) as Map<String, dynamic>,
        );
      }),
    );
  }

  Future<List<int>> _encrypt(List<int> plaintext) async {
    final keyBytes = _encryptionKey;
    final macBytes = _macKey;
    if (keyBytes == null || macBytes == null) throw StateError('Vault is locked.');

    final ivBytes = _secureRandomBytes(16);
    final encrypted = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(keyBytes), mode: encrypt.AESMode.cbc),
    ).encryptBytes(plaintext, iv: encrypt.IV(ivBytes));
    final authenticated = <int>[..._formatMagic, ...ivBytes, ...encrypted.bytes];
    final mac = Hmac.sha256();
    final tag = await mac.calculateMac(
      authenticated,
      secretKey: SecretKey(macBytes),
    );
    return [..._formatMagic, ...ivBytes, ...tag.bytes, ...encrypted.bytes];
  }

  Future<Uint8List> _decrypt(List<int> packed) async {
    final keyBytes = _encryptionKey;
    final macBytes = _macKey;
    const headerLength = 5 + 16 + 32;
    if (keyBytes == null || macBytes == null) throw StateError('Vault is locked.');
    if (packed.length <= headerLength ||
        !listEquals(packed.sublist(0, _formatMagic.length), _formatMagic)) {
      throw const FormatException('Encrypted vault data has an unsupported format.');
    }

    final ivBytes = packed.sublist(5, 21);
    final storedMac = packed.sublist(21, headerLength);
    final ciphertext = packed.sublist(headerLength);
    final authenticated = <int>[..._formatMagic, ...ivBytes, ...ciphertext];
    final expected = await Hmac.sha256().calculateMac(
      authenticated,
      secretKey: SecretKey(macBytes),
    );
    if (!_constantTimeEquals(storedMac, expected.bytes)) {
      throw const FormatException('Encrypted vault data failed authentication.');
    }
    final clear = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(keyBytes), mode: encrypt.AESMode.cbc),
    ).decryptBytes(
      encrypt.Encrypted(Uint8List.fromList(ciphertext)),
      iv: encrypt.IV(Uint8List.fromList(ivBytes)),
    );
    return Uint8List.fromList(clear);
  }

  bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var i = 0; i < left.length; i++) {
      difference |= left[i] ^ right[i];
    }
    return difference == 0;
  }

  String? _categoryFor(String extension) {
    for (final category in categories.entries) {
      if (category.value.contains(extension)) return category.key;
    }
    return null;
  }

  void _requireUnlocked() {
    if (!isUnlocked) throw StateError('Vault is locked.');
  }

  String _newId() => _secureRandomBytes(16)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  Uint8List _secureRandomBytes(int count) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(count, (_) => random.nextInt(256)),
    );
  }

  void _wipe(Uint8List? bytes) {
    if (bytes == null) return;
    bytes.fillRange(0, bytes.length, 0);
  }
}
