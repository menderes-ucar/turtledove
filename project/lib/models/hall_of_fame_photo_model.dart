class HallOfFamePhoto {
  final String id;
  final String ownerId;
  final String? partnerId;
  final String category;
  final String storagePath;
  final String publicUrl;
  final String? note;
  final DateTime createdAt;

  const HallOfFamePhoto({
    required this.id,
    required this.ownerId,
    required this.partnerId,
    required this.category,
    required this.storagePath,
    required this.publicUrl,
    required this.note,
    required this.createdAt,
  });


  HallOfFamePhoto copyWith({String? publicUrl, String? note}) => HallOfFamePhoto(
        id: id,
        ownerId: ownerId,
        partnerId: partnerId,
        category: category,
        storagePath: storagePath,
        publicUrl: publicUrl ?? this.publicUrl,
        note: note ?? this.note,
        createdAt: createdAt,
      );

  factory HallOfFamePhoto.fromMap(Map<String, dynamic> m) => HallOfFamePhoto(
        id: '${m['id']}',
        ownerId: '${m['owner_id']}',
        partnerId: m['partner_id']?.toString(),
        category: '${m['category'] ?? 'mood'}',
        storagePath: '${m['storage_path'] ?? ''}',
        publicUrl: '${m['public_url'] ?? ''}',
        note: m['note']?.toString(),
        createdAt: DateTime.tryParse('${m['created_at']}') ?? DateTime.now(),
      );
}
