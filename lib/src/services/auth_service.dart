import 'package:bcrypt/bcrypt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum AuthResult { master, decoy, rejected }

class AuthService {
  AuthService({FlutterSecureStorage? storage, String? userId})
    : _storage = storage ?? const FlutterSecureStorage(),
      _masterHashKey = userId == null
          ? _legacyMasterHashKey
          : 'secure_vault.$userId.master_bcrypt',
      _decoyHashKey = userId == null
          ? _legacyDecoyHashKey
          : 'secure_vault.$userId.decoy_bcrypt',
      _scopedToUser = userId != null;

  static const _legacyMasterHashKey = 'secure_vault.master_bcrypt';
  static const _legacyDecoyHashKey = 'secure_vault.decoy_bcrypt';

  final FlutterSecureStorage _storage;
  final String _masterHashKey;
  final String _decoyHashKey;
  final bool _scopedToUser;

  Future<bool> isConfigured() async {
    if (await _storage.read(key: _masterHashKey) != null) return true;
    if (!_scopedToUser) return false;

    final legacyHash = await _storage.read(key: _legacyMasterHashKey);
    if (legacyHash == null) return false;
    await _storage.write(key: _masterHashKey, value: legacyHash);
    final legacyDecoyHash = await _storage.read(key: _legacyDecoyHashKey);
    if (legacyDecoyHash != null) {
      await _storage.write(key: _decoyHashKey, value: legacyDecoyHash);
    }
    await _storage.delete(key: _legacyMasterHashKey);
    await _storage.delete(key: _legacyDecoyHashKey);
    return true;
  }

  Future<void> configure(String password, {String? decoyPin}) async {
    await _storage.write(
      key: _masterHashKey,
      value: BCrypt.hashpw(password, BCrypt.gensalt(logRounds: 12)),
    );
    if (decoyPin != null && decoyPin.isNotEmpty) {
      await _storage.write(
        key: _decoyHashKey,
        value: BCrypt.hashpw(decoyPin, BCrypt.gensalt(logRounds: 12)),
      );
    } else {
      await _storage.delete(key: _decoyHashKey);
    }
  }

  Future<void> clearCredentials() async {
    await _storage.delete(key: _masterHashKey);
    await _storage.delete(key: _decoyHashKey);
    if (_scopedToUser) {
      await _storage.delete(key: _legacyMasterHashKey);
      await _storage.delete(key: _legacyDecoyHashKey);
    }
  }

  Future<AuthResult> authenticate(String password) async {
    final masterHash = await _storage.read(key: _masterHashKey);
    if (masterHash == null) {
      throw StateError('The vault has not been configured.');
    }
    if (BCrypt.checkpw(password, masterHash)) return AuthResult.master;

    final decoyHash = await _storage.read(key: _decoyHashKey);
    if (decoyHash != null && BCrypt.checkpw(password, decoyHash)) {
      return AuthResult.decoy;
    }
    return AuthResult.rejected;
  }
}
