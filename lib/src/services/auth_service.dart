import 'package:bcrypt/bcrypt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum AuthResult { master, decoy, rejected }

class AuthService {
  AuthService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _masterHashKey = 'secure_vault.master_bcrypt';
  static const _decoyHashKey = 'secure_vault.decoy_bcrypt';

  final FlutterSecureStorage _storage;

  Future<bool> isConfigured() async =>
      await _storage.read(key: _masterHashKey) != null;

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
