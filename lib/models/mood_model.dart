class MoodEntry {
  final String id;
  final String userId;
  final int mood; // 1-5
  final String? note;
  final String? category; // work, family, relationship, health
  final DateTime createdAt;

  MoodEntry({
    required this.id,
    required this.userId,
    required this.mood,
    this.note,
    this.category,
    required this.createdAt,
  });

  factory MoodEntry.fromMap(Map<String, dynamic> map) => MoodEntry(
    id: map['id'],
    userId: map['user_id'],
    mood: map['mood'],
    note: map['note'],
    category: map['category'],
    createdAt: DateTime.parse(map['created_at']),
  );

  String getEmoji() {
    switch (mood) {
      case 1: return '😢';
      case 2: return '😕';
      case 3: return '😐';
      case 4: return '🙂';
      case 5: return '😄';
      default: return '😐';
    }
  }

  String getMoodText() {
    switch (mood) {
      case 1: return 'Terrible';
      case 2: return 'Bad';
      case 3: return 'Okay';
      case 4: return 'Good';
      case 5: return 'Amazing';
      default: return 'Unknown';
    }
  }
}
