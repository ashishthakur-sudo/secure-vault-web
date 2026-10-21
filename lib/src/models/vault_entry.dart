class VaultEntry {
  const VaultEntry({
    required this.id,
    required this.name,
    required this.category,
    required this.extension,
    required this.createdAt,
    required this.size,
  });

  final String id;
  final String name;
  final String category;
  final String extension;
  final DateTime createdAt;
  final int size;

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'extension': extension,
        'createdAt': createdAt.toIso8601String(),
        'size': size,
      };

  factory VaultEntry.fromJson(Map<String, dynamic> json) => VaultEntry(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
        extension: json['extension'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        size: json['size'] as int,
      );
}
