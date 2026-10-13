import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/message_model.dart';
import 'notification_service.dart';

class ChatService {
  final SupabaseClient client;
  ChatService(this.client);

  Stream<List<Message>> getMessagesStream(String userId, String partnerId) {
    RealtimeChannel? channel;
    late final StreamController<List<Message>> controller;
    var active = true;

    Future<void> emitMessages() async {
      if (!active || controller.isClosed) return;

      try {
        final data = await client
            .from('messages')
            .select()
            .or('and(sender_id.eq.$userId,receiver_id.eq.$partnerId),and(sender_id.eq.$partnerId,receiver_id.eq.$userId)')
            .order('created_at', ascending: true);

        if (!active || controller.isClosed) return;

        final messages = data
            .map((row) => Message.fromMap(Map<String, dynamic>.from(row as Map)))
            .toList(growable: false);

        controller.add(messages);
      } catch (error, stackTrace) {
        if (!active || controller.isClosed) return;
        controller.addError(error, stackTrace);
      }
    }

    Future<void> start() async {
      final session = client.auth.currentSession;
      if (session == null || session.accessToken.isEmpty) {
        if (!controller.isClosed) {
          controller.addError(const AuthException('Realtime requires an active session'));
        }
        return;
      }

      final realtimeChannel = client.channel('bestie-messages-$userId-$partnerId');
      channel = realtimeChannel;

      realtimeChannel
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'messages',
            callback: (_) {
              unawaited(emitMessages());
            },
          )
          .subscribe((status, error) {
            if (!active || controller.isClosed) return;

            if (status == RealtimeSubscribeStatus.subscribed) {
              debugPrint('🟢 BESTIE CHAT Realtime SUBSCRIBED');
              unawaited(emitMessages());
              return;
            }

            if (status == RealtimeSubscribeStatus.channelError ||
                status == RealtimeSubscribeStatus.timedOut) {
              debugPrint('🔴 BESTIE CHAT Realtime status=$status error=$error');
              controller.addError(
                RealtimeSubscribeException(status, error),
              );
            }
          });
    }

    controller = StreamController<List<Message>>(
      sync: false,
      onListen: () {
        unawaited(start());
      },
      onCancel: () async {
        active = false;
        if (channel != null) {
          await client.removeChannel(channel!);
        }
      },
    );

    return controller.stream;
  }

  Future<void> sendMessage(
    String senderId,
    String receiverId,
    String? content,
    String? mediaUrl,
  ) async {
    final currentUser = client.auth.currentUser;
    if (currentUser == null || currentUser.id != senderId) {
      throw const AuthException('You must be signed in to send a message');
    }
    if (senderId == receiverId) {
      throw const FormatException('You cannot send a message to yourself');
    }

    final normalizedContent = content?.trim() ?? '';
    if (normalizedContent.isEmpty &&
        (mediaUrl == null || mediaUrl.trim().isEmpty)) {
      throw const FormatException('Message cannot be empty');
    }

    await client.from('messages').insert({
      'id': const Uuid().v4(),
      'sender_id': senderId,
      'receiver_id': receiverId,
      'content': normalizedContent,
      'media_url': mediaUrl,
      'is_read': false,
      'created_at': DateTime.now().toIso8601String(),
    });
    try {
      await NotificationService(client).create(
        userId: receiverId,
        title: 'Yeni mesaj',
        body: normalizedContent.isNotEmpty ? normalizedContent : 'Yeni bir medya mesajı gönderildi.',
        type: 'message',
        data: {
          'action': normalizedContent.isEmpty ? 'media' : 'text',
        },
      );
    } catch (e) { debugPrint('Notification insert skipped: $e'); }
  }

  Future<void> markMessagesAsRead(String userId, String partnerId) async {
    final currentUser = client.auth.currentUser;
    if (currentUser == null || currentUser.id != userId) {
      throw const AuthException(
        'You must be signed in to mark messages as read',
      );
    }
    if (userId == partnerId) return;

    await client
        .from('messages')
        .update({'is_read': true})
        .eq('sender_id', partnerId)
        .eq('receiver_id', userId)
        .eq('is_read', false);
  }

  Future<String> uploadMedia(XFile file, String userId) async {
    final currentUser = client.auth.currentUser;
    if (currentUser == null || currentUser.id != userId) {
      throw const AuthException('You must be signed in to upload media');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw const FormatException('Selected media is empty');
    final lower = file.name.toLowerCase();
    final ext = lower.contains('.') ? lower.split('.').last : 'bin';
    final path = '$userId/${const Uuid().v4()}.$ext';
    await client.storage.from('messages').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        contentType: _contentTypeForExtension(ext),
        upsert: false,
      ),
    );
    return client.storage.from('messages').getPublicUrl(path);
  }

  String _contentTypeForExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'm4a':
      case 'mp4a':
        return 'audio/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'aac':
        return 'audio/aac';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
      case 'opus':
        return 'audio/ogg';
      case 'caf':
        return 'audio/x-caf';
      case '3gp':
        return 'audio/3gpp';
      case 'amr':
        return 'audio/amr';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'gif':
        return 'image/gif';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'm4v':
        return 'video/x-m4v';
      case 'webm':
        return 'video/webm';
      case 'avi':
        return 'video/x-msvideo';
      default:
        return 'application/octet-stream';
    }
  }

  Future<String> uploadImage(XFile file, String userId) async {
    try {
      final currentUser = client.auth.currentUser;
      if (currentUser == null || currentUser.id != userId) {
        throw const AuthException(
          'You must be signed in to upload an image',
        );
      }

      final fileName = '${const Uuid().v4()}.jpg';
      final fileBytes = await file.readAsBytes();
      await client.storage.from('messages').uploadBinary(
        fileName,
        fileBytes,
        fileOptions: FileOptions(
          contentType: 'image/jpeg',
          upsert: false,
        ),
      );
      return client.storage.from('messages').getPublicUrl(fileName);
    } catch (e) {
      throw Exception('Upload failed: $e');
    }
  }
}
