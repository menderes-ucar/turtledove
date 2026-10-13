class SharedPlace {
  final String id;
  final String userId;
  final String partnerId;
  final String title;
  final String? note;
  final double latitude;
  final double longitude;
  final DateTime createdAt;

  const SharedPlace({
    required this.id,
    required this.userId,
    required this.partnerId,
    required this.title,
    required this.note,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
  });

  factory SharedPlace.fromMap(Map<String, dynamic> map) {
    return SharedPlace(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      partnerId: map['partner_id'] as String,
      title: (map['title'] ?? '') as String,
      note: map['note'] as String?,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
