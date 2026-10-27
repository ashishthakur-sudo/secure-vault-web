import 'dart:convert';
import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'vault_store.dart';

class WebVaultStore implements VaultStore {
  static const _databaseName = 'secure_vault_web';
  static const _settingsStore = 'settings';
  static const _entriesStore = 'entries';
  static const _filesStore = 'files';

  Database? _database;

  @override
  Future<void> create(List<int> salt) async {
    final userId = _requireUserId();
    final remote = await Supabase.instance.client
        .from('vault_settings')
        .select('user_id')
        .eq('user_id', userId)
        .maybeSingle();
    if (remote == null) {
      await Supabase.instance.client.from('vault_settings').insert({
        'user_id': userId,
        'kdf_salt': base64Encode(salt),
      });
    }
    final database = await _openDatabase();
    final transaction = database.transaction([
      _settingsStore,
      _entriesStore,
      _filesStore,
    ], idbModeReadWrite);
    final settings = transaction.objectStore(_settingsStore);
    if (await settings.getObject('salt') == null) {
      await settings.put(Uint8List.fromList(salt), 'salt');
    }
    await transaction.completed;
  }

  @override
  Future<List<int>?> readSalt() async {
    final userId = _requireUserId();
    final remote = await Supabase.instance.client
        .from('vault_settings')
        .select('kdf_salt')
        .eq('user_id', userId)
        .maybeSingle();
    if (remote != null) return base64Decode(remote['kdf_salt'] as String);
    final transaction = (await _openDatabase()).transaction(
      _settingsStore,
      idbModeReadOnly,
    );
    final salt = await transaction
        .objectStore(_settingsStore)
        .getObject('salt');
    await transaction.completed;
    if (salt == null) return null;
    final bytes = Uint8List.fromList((salt as List).cast<int>());
    await Supabase.instance.client.from('vault_settings').insert({
      'user_id': userId,
      'kdf_salt': base64Encode(bytes),
    });
    return bytes;
  }

  @override
  Future<List<StoredVaultRow>> readEntries() async {
    final rows = await Supabase.instance.client
        .from('vault_metadata')
        .select('id,payload')
        .eq('user_id', _requireUserId());
    return rows
        .map(
          (row) => StoredVaultRow(
            row['id'] as String,
            Uint8List.fromList(base64Decode(row['payload'] as String)),
          ),
        )
        .toList();
  }

  @override
  Future<List<StoredVaultRow>> readLegacyEntries() async {
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
    final transaction = database.transaction(_filesStore, idbModeReadWrite);
    await transaction
        .objectStore(_filesStore)
        .put(Uint8List.fromList(file), id);
    await transaction.completed;
    try {
      await Supabase.instance.client.from('vault_metadata').insert({
        'user_id': _requireUserId(),
        'id': id,
        'payload': base64Encode(metadata),
      });
    } catch (_) {
      final rollback = (await _openDatabase()).transaction(
        _filesStore,
        idbModeReadWrite,
      );
      await rollback.objectStore(_filesStore).delete(id);
      await rollback.completed;
      rethrow;
    }
  }

  @override
  Future<void> deleteEntry(String id, String category) async {
    await Supabase.instance.client
        .from('vault_metadata')
        .delete()
        .eq('user_id', _requireUserId())
        .eq('id', id);
    final transaction = (await _openDatabase()).transaction([
      _entriesStore,
      _filesStore,
    ], idbModeReadWrite);
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
    final index = await transaction
        .objectStore(_settingsStore)
        .getObject('legacyIndex');
    await transaction.completed;
    if (index == null) return null;
    return Uint8List.fromList((index as List).cast<int>());
  }

  @override
  Future<void> writeMigratedEntries(List<StoredVaultRow> entries) async {
    if (entries.isEmpty) return;
    await Supabase.instance.client
        .from('vault_metadata')
        .upsert(
          entries
              .map(
                (entry) => {
                  'user_id': _requireUserId(),
                  'id': entry.id,
                  'payload': base64Encode(entry.payload),
                },
              )
              .toList(),
          onConflict: 'user_id,id',
        );
  }

  @override
  Future<void> clearLegacyEntries() async {
    final transaction = (await _openDatabase()).transaction(
      _entriesStore,
      idbModeReadWrite,
    );
    await transaction.objectStore(_entriesStore).clear();
    await transaction.completed;
  }

  @override
  Future<void> reset() async {
    final userId = _requireUserId();
    final remoteRows = await Supabase.instance.client
        .from('vault_metadata')
        .select('id')
        .eq('user_id', userId);
    final ids = remoteRows.map((row) => row['id'] as String).toSet();
    ids.addAll((await readLegacyEntries()).map((row) => row.id));

    final database = await _openDatabase();
    final transaction = database.transaction([
      _settingsStore,
      _entriesStore,
      _filesStore,
    ], idbModeReadWrite);
    final files = transaction.objectStore(_filesStore);
    for (final id in ids) {
      if (RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) {
        await files.delete(id);
      }
    }
    await transaction.objectStore(_entriesStore).clear();
    await transaction.objectStore(_settingsStore).clear();
    await transaction.completed;

    await Supabase.instance.client
        .from('vault_metadata')
        .delete()
        .eq('user_id', userId);
    await Supabase.instance.client
        .from('vault_settings')
        .delete()
        .eq('user_id', userId);
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

  String _requireUserId() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError(
        'Sign in to your cloud account before opening the vault.',
      );
    }
    return userId;
  }
}

VaultStore createVaultStore() => WebVaultStore();
