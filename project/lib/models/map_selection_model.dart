class MapSelection {
  final String id;
  final String userId;
  final String partnerId;
  final String countryCode;
  final String countryName;
  final String? cityName;
  final String? stateName;
  final int? cityId;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;

  const MapSelection({
    required this.id,
    required this.userId,
    required this.partnerId,
    required this.countryCode,
    required this.countryName,
    required this.cityName,
    required this.stateName,
    required this.cityId,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
  });

  factory MapSelection.fromMap(Map<String, dynamic> map) {
    return MapSelection(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      partnerId: map['partner_id'] as String,
      countryCode: (map['country_code'] ?? '') as String,
      countryName: (map['country_name'] ?? '') as String,
      cityName: map['city_name'] as String?,
      stateName: map['state_name'] as String?,
      cityId: (map['city_id'] as num?)?.toInt(),
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
