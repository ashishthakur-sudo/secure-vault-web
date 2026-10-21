import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_vault/src/models/vault_entry.dart';
import 'package:secure_vault/src/services/vault_service.dart';
import 'package:secure_vault/src/services/vault_store.dart';

void main() {
  test('unlock decrypts saved entry metadata before decoding it', () async {
    const password = 'test-password';
    final salt = Uint8List.fromList(List<int>.generate(16, (index) => index));
    final entry = VaultEntry(
      id: '00112233445566778899aabbccddeeff',
      name: 'photo.png',
      category: 'Images',
      extension: 'png',
      createdAt: DateTime.utc(2025, 1, 1),
      size: 42,
    );
    final store = _MemoryVaultStore(salt: salt)
      ..rows.add(
        StoredVaultRow(entry.id, await _encryptMetadata(entry, password, salt)),
      );
    final service = VaultService(store: store);

    await service.unlock(password);

    expect(service.entries.single.toJson(), entry.toJson());
  });
}

Future<Uint8List> _encryptMetadata(
  VaultEntry entry,
  String password,
  List<int> salt,
) async {
  const magic = [83, 86, 76, 84, 1];
  final key = await Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 210000,
    bits: 512,
  ).deriveKeyFromPassword(password: password, nonce: salt);
  final keyBytes = await key.extractBytes();
  final iv = Uint8List.fromList(List<int>.generate(16, (index) => 15 - index));
  final ciphertext = encrypt.Encrypter(
    encrypt.AES(
      encrypt.Key(Uint8List.fromList(keyBytes.sublist(0, 32))),
      mode: encrypt.AESMode.cbc,
    ),
  ).encryptBytes(
    utf8.encode(jsonEncode(entry.toJson())),
    iv: encrypt.IV(iv),
  ).bytes;
  final authenticated = <int>[...magic, ...iv, ...ciphertext];
  final tag = await Hmac.sha256().calculateMac(
    authenticated,
    secretKey: SecretKey(keyBytes.sublist(32, 64)),
  );
  return Uint8List.fromList([...magic, ...iv, ...tag.bytes, ...ciphertext]);
}

class _MemoryVaultStore implements VaultStore {
  _MemoryVaultStore({required this.salt});

  final Uint8List salt;
  final List<StoredVaultRow> rows = [];

  @override
  Future<void> create(List<int> salt) async {}

  @override
  Future<void> clearLegacyIndex() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> deleteEntry(String id, String category) async {
    rows.removeWhere((row) => row.id == id);
  }

  @override
  Future<List<int>?> readFile(String id, String category) async => null;

  @override
  Future<List<int>?> readLegacyIndex() async => null;

  @override
  Future<List<StoredVaultRow>> readEntries() async => rows;

  @override
  Future<List<int>?> readSalt() async => salt;

  @override
  Future<void> writeEntry(
    String id,
    String category,
    List<int> file,
    List<int> metadata,
  ) async {
    rows.add(StoredVaultRow(id, Uint8List.fromList(metadata)));
  }

  @override
  Future<void> writeMigratedEntries(List<StoredVaultRow> entries) async {
    rows.addAll(entries);
  }
}
