class Interaction {
  final String id, senderId, receiverId, type;
  final DateTime createdAt;

  Interaction({required this.id, required this.senderId, required this.receiverId, required this.type, required this.createdAt});

  factory Interaction.fromMap(Map<String, dynamic> m) => Interaction(
    id: m['id'], senderId: m['sender_id'], receiverId: m['receiver_id'],
    type: m['type'], createdAt: DateTime.parse(m['created_at']),
  );

  String getEmoji() => {'hug': '🫂', 'kiss': '💋', 'nudge': '👉', 'miss_you': '🥺', 'infinity': '∞'}[type] ?? '💕';
  String getMessage(String name) => '$name ${{'hug': 'sent you a hug!', 'kiss': 'sent you a kiss!', 'nudge': 'nudged you!', 'miss_you': 'says they miss you!', 'infinity': 'sent you forever ∞'}[type] ?? 'sent you something!'}';
}
