class Profile {
  final String id, username, pairCode;
  final String? avatarUrl, pairedWith, status;
  final DateTime createdAt, updatedAt;
  final DateTime? lastSeenAt;

  Profile({
    required this.id,
    required this.username,
    required this.pairCode,
    this.avatarUrl,
    this.pairedWith,
    this.status,
    this.lastSeenAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
    id: m['id'] as String,
    username: (m['username'] ?? '') as String,
    pairCode: (m['pair_code'] ?? '') as String,
    avatarUrl: m['avatar_url'] as String?,
    pairedWith: m['paired_with'] as String?,
    status: m['status'] as String?,
    lastSeenAt: m['last_seen_at'] == null ? null : DateTime.tryParse(m['last_seen_at'].toString()),
    createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(m['updated_at']?.toString() ?? '') ?? DateTime.now(),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'username': username,
    'pair_code': pairCode,
    'avatar_url': avatarUrl,
    'paired_with': pairedWith,
    'status': status,
    'last_seen_at': lastSeenAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  Profile copyWith({
    String? username,
    String? avatarUrl,
    String? pairedWith,
    String? status,
    DateTime? lastSeenAt,
    DateTime? updatedAt,
  }) => Profile(
    id: id,
    username: username ?? this.username,
    pairCode: pairCode,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    pairedWith: pairedWith ?? this.pairedWith,
    status: status ?? this.status,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
  );
}
