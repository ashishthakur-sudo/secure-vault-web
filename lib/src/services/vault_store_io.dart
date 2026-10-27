import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'vault_store.dart';

class IoVaultStore implements VaultStore {
  static const _saltName = '.kdf-salt';
  static const _legacyIndexName = '.index.svlt';
  static const _databaseName = '.vault-metadata.db';
  static const _categories = ['Images', 'PDFs', 'Videos', 'Audios'];

  String? _rootPath;
  Database? _database;

  @override
  Future<void> create(List<int> salt) async {
    final documents = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(documents.path, '.SecureVault'));
    await root.create(recursive: true);
    for (final category in _categories) {
      await Directory(p.join(root.path, category)).create(recursive: true);
    }
    _rootPath = root.path;
    final localSalt = File(p.join(root.path, _saltName));
    if (!await localSalt.exists()) {
      await localSalt.writeAsBytes(salt, flush: true);
    }
    final userId = _requireUserId();
    final existing = await Supabase.instance.client
        .from('vault_settings')
        .select('user_id')
        .eq('user_id', userId)
        .maybeSingle();
    if (existing == null) {
      await Supabase.instance.client.from('vault_settings').insert({
        'user_id': userId,
        'kdf_salt': base64Encode(salt),
      });
    }
  }

  @override
  Future<List<int>?> readSalt() async {
    final userId = _requireUserId();
    final remote = await Supabase.instance.client
        .from('vault_settings')
        .select('kdf_salt')
        .eq('user_id', userId)
        .maybeSingle();
    if (remote != null) {
      return base64Decode(remote['kdf_salt'] as String);
    }
    final root = await _root();
    final saltFile = File(p.join(root, _saltName));
    if (!await saltFile.exists()) return null;
    final salt = await saltFile.readAsBytes();
    await Supabase.instance.client.from('vault_settings').insert({
      'user_id': userId,
      'kdf_salt': base64Encode(salt),
    });
    return salt;
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
    final legacyFile = File(p.join(await _root(), _databaseName));
    if (!await legacyFile.exists()) return [];
    final rows = await (await _openDatabase()).query(
      'entries',
      orderBy: 'rowid',
    );
    return rows
        .map(
          (row) => StoredVaultRow(
            row['id']! as String,
            Uint8List.fromList(row['payload']! as List<int>),
          ),
        )
        .toList();
  }

  @override
  Future<void> writeEntry(
    String id,
    String category,
    List<int> file,
    List<int> metadata,
  ) async {
    final output = File(p.join(await _categoryPath(category), '$id.svlt'));
    await output.writeAsBytes(file, flush: true);
    try {
      await Supabase.instance.client.from('vault_metadata').insert({
        'user_id': _requireUserId(),
        'id': id,
        'payload': base64Encode(metadata),
      });
    } catch (_) {
      if (await output.exists()) await output.delete();
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
    final file = File(p.join(await _categoryPath(category), '$id.svlt'));
    if (await file.exists()) await file.delete();
  }

  @override
  Future<List<int>?> readFile(String id, String category) async {
    final file = File(p.join(await _categoryPath(category), '$id.svlt'));
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<List<int>?> readLegacyIndex() async {
    final file = File(p.join(await _root(), _legacyIndexName));
    if (!await file.exists()) return null;
    return file.readAsBytes();
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
    final legacyFile = File(p.join(await _root(), _databaseName));
    if (!await legacyFile.exists()) return;
    await (await _openDatabase()).delete('entries');
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

    for (final id in ids) {
      if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) continue;
      for (final category in _categories) {
        final file = File(p.join(await _categoryPath(category), '$id.svlt'));
        if (await file.exists()) await file.delete();
      }
    }

    await Supabase.instance.client
        .from('vault_metadata')
        .delete()
        .eq('user_id', userId);
    await Supabase.instance.client
        .from('vault_settings')
        .delete()
        .eq('user_id', userId);

    await close();
    final root = await _root();
    for (final name in [_saltName, _legacyIndexName, _databaseName]) {
      final file = File(p.join(root, name));
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<void> clearLegacyIndex() async {
    final file = File(p.join(await _root(), _legacyIndexName));
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> close() async {
    final database = _database;
    _database = null;
    _rootPath = null;
    if (database != null && database.isOpen) await database.close();
  }

  Future<String> _root() async {
    return _rootPath ??= p.join(
      (await getApplicationDocumentsDirectory()).path,
      '.SecureVault',
    );
  }

  Future<String> _categoryPath(String category) async {
    if (!_categories.contains(category)) {
      throw ArgumentError.value(category, 'category', 'Unknown vault folder');
    }
    final path = p.join(await _root(), category);
    await Directory(path).create(recursive: true);
    return path;
  }

  Future<Database> _openDatabase() async {
    final current = _database;
    if (current != null && current.isOpen) return current;

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
    }
    final factory = Platform.isWindows || Platform.isLinux || Platform.isMacOS
        ? databaseFactoryFfi
        : sqflite.databaseFactory;
    final database = await factory.openDatabase(
      p.join(await _root(), _databaseName),
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (database) async {
          await database.execute('PRAGMA secure_delete = ON');
          await database.execute('PRAGMA journal_mode = DELETE');
        },
        onCreate: (database, version) async {
          await database.execute(
            'CREATE TABLE entries (id TEXT PRIMARY KEY, payload BLOB NOT NULL)',
          );
        },
      ),
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

VaultStore createVaultStore() => IoVaultStore();
