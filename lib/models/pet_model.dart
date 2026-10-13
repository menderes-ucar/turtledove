class PetModel {
  static const int maxLevel = 1000;
  static const int xpPerLevel = 1000;

  final String id;
  final String name;
  final String species;
  final String breed;
  final int level;
  final int xp;
  final int hunger;
  final int hygiene;
  final int energy;
  final int fun;
  final int affection;
  final int health;
  final int toilet;
  final int coins;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastFedAt;
  final DateTime? lastBathAt;
  final DateTime? lastPlayedAt;
  final DateTime? lastToiletAt;
  final DateTime? lastNailAt;

  const PetModel({
    required this.id,
    required this.name,
    required this.species,
    required this.breed,
    required this.level,
    required this.xp,
    required this.hunger,
    required this.hygiene,
    required this.energy,
    required this.fun,
    required this.affection,
    required this.health,
    required this.toilet,
    required this.coins,
    required this.createdAt,
    required this.updatedAt,
    required this.lastFedAt,
    required this.lastBathAt,
    required this.lastPlayedAt,
    required this.lastToiletAt,
    required this.lastNailAt,
  });

  factory PetModel.fromMap(Map<String, dynamic> map) => PetModel(
        id: map['id'].toString(),
        name: (map['name'] ?? 'Bestie').toString(),
        species: (map['species'] ?? 'cat').toString(),
        breed: (map['breed'] ?? '').toString(),
        level: _int(map['level'], 1).clamp(1, maxLevel),
        xp: _int(map['xp'], 0).clamp(0, xpPerLevel - 1),
        hunger: _int(map['hunger'], 100).clamp(0, 100),
        hygiene: _int(map['hygiene'], 100).clamp(0, 100),
        energy: _int(map['energy'], 100).clamp(0, 100),
        fun: _int(map['fun'], 100).clamp(0, 100),
        affection: _int(map['affection'], 50).clamp(0, 100),
        health: _int(map['health'], 100).clamp(0, 100),
        toilet: _int(map['toilet'], 100).clamp(0, 100),
        coins: _int(map['coins'], 0).clamp(0, 999999999),
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? DateTime.now(),
        lastFedAt: _date(map['last_fed_at']),
        lastBathAt: _date(map['last_bath_at']),
        lastPlayedAt: _date(map['last_played_at']),
        lastToiletAt: _date(map['last_toilet_at']),
        lastNailAt: _date(map['last_nail_at']),
      );

  static int _int(dynamic value, int fallback) => value is num ? value.round() : fallback;
  static DateTime? _date(dynamic value) => value == null ? null : DateTime.tryParse(value.toString());

  String get stageKey {
    if (level <= 150) return 'baby';
    if (level <= 300) return 'child';
    if (level <= 450) return 'young';
    if (level <= 600) return 'teen';
    if (level <= 750) return 'adult';
    if (level <= 900) return 'mature';
    return 'senior';
  }

  String get speciesEmoji => switch (species) {
        'dog' => '🐶',
        'cat' => '🐱',
        'rabbit' => '🐰',
        'bird' => '🐦',
        'hamster' => '🐹',
        'fox' => '🦊',
        'snake' => '🐍',
        _ => '🐾',
      };

  int get xpForCurrentLevel => level >= maxLevel ? 0 : xpPerLevel;
  double get levelProgress => level >= maxLevel ? 1 : (xp / xpPerLevel).clamp(0, 1).toDouble();

  PetModel copyWith({
    String? name,
    String? species,
    String? breed,
    int? level,
    int? xp,
    int? hunger,
    int? hygiene,
    int? energy,
    int? fun,
    int? affection,
    int? health,
    int? toilet,
    int? coins,
    DateTime? updatedAt,
  }) => PetModel(
        id: id,
        name: name ?? this.name,
        species: species ?? this.species,
        breed: breed ?? this.breed,
        level: level ?? this.level,
        xp: xp ?? this.xp,
        hunger: hunger ?? this.hunger,
        hygiene: hygiene ?? this.hygiene,
        energy: energy ?? this.energy,
        fun: fun ?? this.fun,
        affection: affection ?? this.affection,
        health: health ?? this.health,
        toilet: toilet ?? this.toilet,
        coins: coins ?? this.coins,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        lastFedAt: lastFedAt,
        lastBathAt: lastBathAt,
        lastPlayedAt: lastPlayedAt,
        lastToiletAt: lastToiletAt,
        lastNailAt: lastNailAt,
      );
}
