import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart';

import 'vault_store.dart';

class WebVaultStore implements VaultStore {
  static const _databaseName = 'secure_vault_web';
  static const _settingsStore = 'settings';
  static const _entriesStore = 'entries';
  static const _filesStore = 'files';

  Database? _database;

  @override
  Future<void> create(List<int> salt) async {
    final database = await _openDatabase();
    final transaction = database.transaction(
      [_settingsStore, _entriesStore, _filesStore],
      idbModeReadWrite,
    );
    await transaction.objectStore(_settingsStore).put(Uint8List.fromList(salt), 'salt');
    await transaction.objectStore(_entriesStore).clear();
    await transaction.objectStore(_filesStore).clear();
    await transaction.completed;
  }

  @override
  Future<List<int>?> readSalt() async {
    final transaction = (await _openDatabase()).transaction(
      _settingsStore,
      idbModeReadOnly,
    );
    final salt = await transaction.objectStore(_settingsStore).getObject('salt');
    await transaction.completed;
    if (salt == null) return null;
    return Uint8List.fromList((salt as List).cast<int>());
  }

  @override
  Future<List<StoredVaultRow>> readEntries() async {
    final transaction = (await _openDatabase()).transaction(
      _entriesStore,
      idbModeReadOnly,
    );
    final store = transaction.objectStore(_entriesStore);
    final keys = await store.getAllKeys();
    final values = await store.getAll();
    await transaction.completed;
    return List<StoredVaultRow>.generate(
      keys.length,
      (index) => StoredVaultRow(
        keys[index] as String,
        Uint8List.fromList((values[index] as List).cast<int>()),
      ),
    );
  }

  @override
  Future<void> writeEntry(
    String id,
    String category,
    List<int> file,
    List<int> metadata,
  ) async {
    final database = await _openDatabase();
    final transaction = database.transaction(
      [_entriesStore, _filesStore],
      idbModeReadWrite,
    );
    await transaction.objectStore(_filesStore).put(Uint8List.fromList(file), id);
    await transaction.objectStore(_entriesStore).put(
          Uint8List.fromList(metadata),
          id,
        );
    await transaction.completed;
  }

  @override
  Future<void> deleteEntry(String id, String category) async {
    final transaction = (await _openDatabase()).transaction(
      [_entriesStore, _filesStore],
      idbModeReadWrite,
    );
    await transaction.objectStore(_entriesStore).delete(id);
    await transaction.objectStore(_filesStore).delete(id);
    await transaction.completed;
  }

  @override
  Future<List<int>?> readFile(String id, String category) async {
    final transaction = (await _openDatabase()).transaction(
      _filesStore,
      idbModeReadOnly,
    );
    final file = await transaction.objectStore(_filesStore).getObject(id);
    await transaction.completed;
    if (file == null) return null;
    return Uint8List.fromList((file as List).cast<int>());
  }

  @override
  Future<List<int>?> readLegacyIndex() async {
    final transaction = (await _openDatabase()).transaction(
      _settingsStore,
      idbModeReadOnly,
    );
    final index = await transaction.objectStore(_settingsStore).getObject('legacyIndex');
    await transaction.completed;
    if (index == null) return null;
    return Uint8List.fromList((index as List).cast<int>());
  }

  @override
  Future<void> writeMigratedEntries(List<StoredVaultRow> entries) async {
    final transaction = (await _openDatabase()).transaction(
      _entriesStore,
      idbModeReadWrite,
    );
    final store = transaction.objectStore(_entriesStore);
    for (final entry in entries) {
      await store.put(entry.payload, entry.id);
    }
    await transaction.completed;
  }

  @override
  Future<void> clearLegacyIndex() async {
    final transaction = (await _openDatabase()).transaction(
      _settingsStore,
      idbModeReadWrite,
    );
    await transaction.objectStore(_settingsStore).delete('legacyIndex');
    await transaction.completed;
  }

  @override
  Future<void> close() async {
    _database?.close();
    _database = null;
  }

  Future<Database> _openDatabase() async {
    final current = _database;
    if (current != null) return current;
    final database = await idbFactoryBrowser.open(
      _databaseName,
      version: 1,
      onUpgradeNeeded: (event) {
        final database = event.database;
        database.createObjectStore(_settingsStore);
        database.createObjectStore(_entriesStore);
        database.createObjectStore(_filesStore);
      },
    );
    _database = database;
    return database;
  }
}

VaultStore createVaultStore() => WebVaultStore();
