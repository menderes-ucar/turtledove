class Message {
  final String id, senderId, receiverId;
  final String? content, mediaUrl;
  final bool isRead;
  final DateTime createdAt;

  Message({
    required this.id, required this.senderId, required this.receiverId,
    this.content, this.mediaUrl, required this.isRead, required this.createdAt,
  });

  factory Message.fromMap(Map<String, dynamic> m) => Message(
    id: m['id'], senderId: m['sender_id'], receiverId: m['receiver_id'],
    content: m['content'], mediaUrl: m['media_url'],
    isRead: m['is_read'] ?? false, createdAt: DateTime.parse(m['created_at']),
  );

  bool get hasMedia => mediaUrl != null && mediaUrl!.isNotEmpty;
  bool get isVideo {
    final url = mediaUrl?.toLowerCase() ?? '';
    return RegExp(r'\.(mp4|mov|m4v|webm|avi)(?:[?#].*)?$').hasMatch(url);
  }

  bool get isAudio {
    final url = mediaUrl?.toLowerCase() ?? '';
    return RegExp(r'\.(m4a|mp3|aac|wav|ogg|opus|caf|3gp|amr)(?:[?#].*)?$')
        .hasMatch(url);
  }

  bool get isImage => hasMedia && !isVideo && !isAudio;
}
