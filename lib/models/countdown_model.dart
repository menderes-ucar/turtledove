class Countdown {
  final String id;
  final String userId;
  final String title;
  final DateTime targetDate;
  final String type; // anniversary, visit, birthday, custom
  final String? emoji;
  final DateTime createdAt;

  Countdown({
    required this.id,
    required this.userId,
    required this.title,
    required this.targetDate,
    required this.type,
    this.emoji,
    required this.createdAt,
  });

  factory Countdown.fromMap(Map<String, dynamic> map) => Countdown(
    id: map['id'],
    userId: map['user_id'],
    title: map['title'],
    targetDate: DateTime.parse(map['target_date']),
    type: map['type'],
    emoji: map['emoji'],
    createdAt: DateTime.parse(map['created_at']),
  );

  Duration get remainingDuration => targetDate.difference(DateTime.now());
  int get daysRemaining {
    final duration = remainingDuration;
    if (duration.isNegative) return 0;
    if (duration == Duration.zero) return 0;
    return (duration.inMilliseconds / Duration.millisecondsPerDay).ceil();
  }

  bool get isToday {
    final now = DateTime.now();
    return !isPast &&
        targetDate.year == now.year &&
        targetDate.month == now.month &&
        targetDate.day == now.day;
  }
  bool get isPast => remainingDuration.isNegative;

  String getEmoji() {
    if (emoji != null) return emoji!;
    switch (type) {
      case 'anniversary': return '💑';
      case 'visit': return '✈️';
      case 'birthday': return '🎂';
      default: return '📅';
    }
  }
}
