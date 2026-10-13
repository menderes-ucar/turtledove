import 'package:flutter_test/flutter_test.dart';
import 'package:bestie/models/message_model.dart';

Message _message(String mediaUrl) => Message(
      id: 'message-id',
      senderId: 'sender-id',
      receiverId: 'receiver-id',
      mediaUrl: mediaUrl,
      isRead: false,
      createdAt: DateTime.utc(2026, 10, 13),
    );

void main() {
  group('Message audio media detection', () {
    test('recognizes m4a voice messages and does not render them as images', () {
      final message = _message(
        'https://example.supabase.co/storage/v1/object/public/messages/user-id/voice.m4a?token=abc',
      );

      expect(message.isAudio, isTrue);
      expect(message.isVideo, isFalse);
      expect(message.isImage, isFalse);
    });

    test('keeps existing video media detection', () {
      final message = _message('https://example.com/clip.mp4');

      expect(message.isVideo, isTrue);
      expect(message.isAudio, isFalse);
      expect(message.isImage, isFalse);
    });

    test('keeps existing image media detection', () {
      final message = _message('https://example.com/photo.jpg');

      expect(message.isImage, isTrue);
      expect(message.isAudio, isFalse);
      expect(message.isVideo, isFalse);
    });
  });
}
