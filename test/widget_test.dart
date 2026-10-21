import 'package:flutter_test/flutter_test.dart';
import 'package:secure_vault/src/models/vault_entry.dart';

void main() {
  test('vault entry survives JSON serialization', () {
    final entry = VaultEntry(
      id: '001122',
      name: 'photo.png',
      category: 'Images',
      extension: 'png',
      createdAt: DateTime.utc(2025, 1, 1),
      size: 42,
    );

    final restored = VaultEntry.fromJson(
      Map<String, dynamic>.from(entry.toJson()),
    );

    expect(restored.id, entry.id);
    expect(restored.name, entry.name);
    expect(restored.category, entry.category);
    expect(restored.extension, entry.extension);
    expect(restored.createdAt, entry.createdAt);
    expect(restored.size, entry.size);
  });
}
