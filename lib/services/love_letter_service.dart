import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'notification_service.dart';

class LoveLetter {
  final String id;
  final String senderId;
  final String receiverId;
  final String content;
  final DateTime? scheduledFor;
  final DateTime createdAt;
  final bool isRead;

  LoveLetter({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    this.scheduledFor,
    required this.createdAt,
    required this.isRead,
  });

  factory LoveLetter.fromMap(Map<String, dynamic> map) => LoveLetter(
        id: map['id'].toString(),
        senderId: map['sender_id'].toString(),
        receiverId: map['receiver_id'].toString(),
        content: (map['content'] ?? '').toString(),
        scheduledFor: map['scheduled_for'] != null
            ? DateTime.tryParse(map['scheduled_for'].toString())
            : null,
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
        isRead: map['is_read'] == true,
      );
}

class LoveLetterService {
  final SupabaseClient client;
  LoveLetterService(this.client);

  Stream<List<LoveLetter>> getLettersStream(String userId, String partnerId) {
    return client
        .from('love_letters')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((data) => data
            .where((row) {
              final letter = Map<String, dynamic>.from(row);
              final sender = letter['sender_id']?.toString();
              final receiver = letter['receiver_id']?.toString();
              return (sender == userId && receiver == partnerId) ||
                  (sender == partnerId && receiver == userId);
            })
            .map((row) => LoveLetter.fromMap(Map<String, dynamic>.from(row)))
            .toList());
  }

  Future<LoveLetter> getLetter(String letterId) async {
    final row = await client
        .from('love_letters')
        .select()
        .eq('id', letterId)
        .maybeSingle();
    if (row == null) {
      throw const PostgrestException(message: 'Letter not found');
    }
    return LoveLetter.fromMap(Map<String, dynamic>.from(row));
  }

  Future<String> getProfileName(String userId) async {
    final row = await client
        .from('profiles')
        .select('username')
        .eq('id', userId)
        .maybeSingle();
    return (row?['username'] ?? 'Partner').toString();
  }

  Future<void> sendLetter(
    String senderId,
    String receiverId,
    String content, {
    DateTime? scheduledFor,
  }) async {
    final currentUser = client.auth.currentUser;
    if (currentUser == null || currentUser.id != senderId) {
      throw const AuthException('You must be signed in to send a letter');
    }

    final normalizedContent = content.trim();
    if (normalizedContent.isEmpty) {
      throw const FormatException('Letter cannot be empty');
    }
    if (senderId == receiverId) {
      throw const FormatException('You cannot send a letter to yourself');
    }
    if (scheduledFor != null && !scheduledFor.isAfter(DateTime.now())) {
      throw const FormatException('Scheduled time must be in the future');
    }

    final letterId = const Uuid().v4();
    await client.from('love_letters').insert({
      'id': letterId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'content': normalizedContent,
      'scheduled_for': scheduledFor?.toUtc().toIso8601String(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'is_read': false,
    });

    // Immediate letters create the notification now. Scheduled letters are
    // delivered by the database due-letter job at scheduled_for.
    if (scheduledFor == null) {
      try {
        await NotificationService(client).create(
          userId: receiverId,
          title: 'Yeni mektup 💌',
          body: normalizedContent.length > 80
              ? '${normalizedContent.substring(0, 80)}…'
              : normalizedContent,
          type: 'love_letter',
          data: {'letter_id': letterId},
        );
      } catch (_) {}
    }
  }

  Future<void> markAsRead(String letterId) async {
    final currentUser = client.auth.currentUser;
    if (currentUser == null) {
      throw const AuthException('You must be signed in to read a letter');
    }

    await client
        .from('love_letters')
        .update({'is_read': true})
        .eq('id', letterId)
        .eq('receiver_id', currentUser.id);
  }
}
