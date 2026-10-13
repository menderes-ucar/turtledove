import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/todo_model.dart';
import 'notification_service.dart';

class TodoService {
  final SupabaseClient client;
  TodoService(this.client);

  Stream<List<TodoItem>> getTodosStream(String userId, String partnerId) {
    RealtimeChannel? channel;
    late final StreamController<List<TodoItem>> controller;
    var active = true;

    Future<void> emitTodos() async {
      if (!active || controller.isClosed) return;

      try {
        final data = await client
            .from('todos')
            .select()
            .order('created_at', ascending: true);

        if (!active || controller.isClosed) return;

        final todos = data
            .where((row) {
              final todo = row as Map<String, dynamic>;
              return (todo['user_id'] == userId &&
                      todo['partner_id'] == partnerId) ||
                  (todo['user_id'] == partnerId &&
                      todo['partner_id'] == userId);
            })
            .map((row) => TodoItem.fromMap(row as Map<String, dynamic>))
            .toList();

        controller.add(todos);
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

      final realtimeChannel = client.channel('bestie-todos-$userId-$partnerId');
      channel = realtimeChannel;

      realtimeChannel
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'todos',
            callback: (_) {
              unawaited(emitTodos());
            },
          )
          .subscribe((status, error) {
            if (!active || controller.isClosed) return;

            if (status == RealtimeSubscribeStatus.subscribed) {
              debugPrint('🟢 BESTIE TODO Realtime SUBSCRIBED');
              unawaited(emitTodos());
              return;
            }

            if (status == RealtimeSubscribeStatus.channelError ||
                status == RealtimeSubscribeStatus.timedOut) {
              debugPrint('🔴 BESTIE TODO Realtime status=$status error=$error');
              controller.addError(
                RealtimeSubscribeException(status, error),
              );
            }
          });
    }

    controller = StreamController<List<TodoItem>>(
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

  Future<void> addTodo(String userId, String partnerId, String title) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw const FormatException('Task title cannot be empty');
    }

    final currentUser = client.auth.currentUser;
    if (currentUser == null || currentUser.id != userId) {
      throw const AuthException('You must be signed in to add a task');
    }

    if (userId == partnerId) {
      throw const FormatException('You cannot create a task with yourself');
    }

    await client.from('todos').insert({
      'id': const Uuid().v4(),
      'user_id': userId,
      'partner_id': partnerId,
      'title': normalizedTitle,
      'is_completed': false,
      'completed_by': null,
      'completed_at': null,
      'created_at': DateTime.now().toIso8601String(),
    });
    try {
      await NotificationService(client).create(userId: partnerId, title: 'Yeni görev', body: normalizedTitle, type: 'todo', data: {'action': 'todo_created'});
    } catch (e) { debugPrint('Todo notification skipped: $e'); }
  }

  Future<void> toggleTodo(String todoId, bool isCompleted) async {
    final currentUser = client.auth.currentUser;
    if (currentUser == null) {
      throw const AuthException('You must be signed in to update a task');
    }

    final nextCompleted = !isCompleted;
    await client.from('todos').update({
      'is_completed': nextCompleted,
      'completed_by': nextCompleted ? currentUser.id : null,
      'completed_at':
          nextCompleted ? DateTime.now().toIso8601String() : null,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', todoId);

    try {
      final todo = await client.from('todos').select('title,user_id,partner_id').eq('id', todoId).maybeSingle();
      if (todo != null) {
        final ownerId = todo['user_id']?.toString();
        final partnerId = todo['partner_id']?.toString();
        final receiverId = ownerId == currentUser.id ? partnerId : ownerId;
        if (receiverId != null && receiverId.isNotEmpty && receiverId != currentUser.id) {
          await NotificationService(client).create(
            userId: receiverId,
            title: nextCompleted ? 'Görev tamamlandı ✅' : 'Görev yeniden açıldı',
            body: (todo['title'] ?? 'Görev').toString(),
            type: 'todo',
            data: {'action': nextCompleted ? 'completed' : 'reopened', 'todo_id': todoId},
          );
        }
      }
    } catch (e) {
      debugPrint('Todo completion notification skipped: $e');
    }
  }

  Future<void> deleteTodo(String todoId) async {
    final currentUser = client.auth.currentUser;
    if (currentUser == null) {
      throw const AuthException('You must be signed in to delete a task');
    }

    await client.from('todos').delete().eq('id', todoId);
  }
}
