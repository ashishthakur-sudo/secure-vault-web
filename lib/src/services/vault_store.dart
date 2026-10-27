import 'dart:typed_data';

import 'vault_store_stub.dart'
    if (dart.library.io) 'vault_store_io.dart'
    if (dart.library.js_interop) 'vault_store_web.dart'
    as platform;

class StoredVaultRow {
  const StoredVaultRow(this.id, this.payload);

  final String id;
  final Uint8List payload;
}

abstract interface class VaultStore {
  Future<void> create(List<int> salt);
  Future<List<int>?> readSalt();
  Future<List<StoredVaultRow>> readEntries();
  Future<List<StoredVaultRow>> readLegacyEntries();
  Future<void> writeEntry(
    String id,
    String category,
    List<int> file,
    List<int> metadata,
  );
  Future<void> deleteEntry(String id, String category);
  Future<List<int>?> readFile(String id, String category);
  Future<List<int>?> readLegacyIndex();
  Future<void> writeMigratedEntries(List<StoredVaultRow> entries);
  Future<void> clearLegacyEntries();
  Future<void> reset();
  Future<void> clearLegacyIndex();
  Future<void> close();
}

VaultStore createVaultStore() => platform.createVaultStore();
