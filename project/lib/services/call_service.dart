import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/call_signal_model.dart';
import 'notification_service.dart';

/// Durable call lifecycle plus low-latency Realtime signaling.
class CallService {
  final SupabaseClient client;
  CallService(this.client);

  RealtimeChannel? _signalChannel;
  final _signals = StreamController<CallSignal>.broadcast();
  String? _userId;
  String? _partnerId;
  final Set<String> _deliveredSignalIds = <String>{};
  final Set<String> _incomingUiClaims = <String>{};

  Stream<CallSignal> get signals => _signals.stream;

  /// There must be exactly one incoming-call UI per call ID in a running
  /// Flutter process. Notification navigation and the HomeScreen database
  /// recovery listener can legitimately race; this in-memory claim makes the
  /// route creation atomic between those two entry points.
  bool claimIncomingCallUi(String callId) {
    if (callId.isEmpty) return false;
    return _incomingUiClaims.add(callId);
  }

  void releaseIncomingCallUi(String callId) {
    if (callId.isNotEmpty) _incomingUiClaims.remove(callId);
  }

  Future<void> connect({required String userId, required String partnerId, String? callId}) async {
    final sameConnection =
        _userId == userId && _partnerId == partnerId && _signalChannel != null;

    if (!sameConnection) {
      await disconnect();
      _userId = userId;
      _partnerId = partnerId;

      final channel = client.channel('bestie-call-signals-$userId-$partnerId');
      _signalChannel = channel;

      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'call_signals',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'to_user_id',
          value: userId,
        ),
        callback: (payload) {
          _emitSignal(payload.newRecord);
        },
      ).subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          debugPrint('🟢 BESTIE CALL SIGNAL REALTIME READY user=$userId');
        } else if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut) {
          debugPrint('🔴 BESTIE CALL SIGNAL REALTIME status=$status error=$error');
        }
      });
    }

    // HomeScreen keeps the participant-level signal channel alive while the
    // app is open. A call screen may then connect to the same channel with a
    // callId; in that case we STILL load this call's durable backlog. This is
    // important for hangup/reject events that happened just before the UI was
    // created and prevents stale incoming screens from surviving a cancelled
    // call.
    if (callId != null && callId.isNotEmpty) {
      try {
        final rows = await client
            .from('call_signals')
            .select()
            .eq('to_user_id', userId)
            .eq('call_id', callId)
            .order('created_at', ascending: true);
        for (final row in rows) {
          _emitSignal(Map<String, dynamic>.from(row as Map));
        }
      } catch (e) {
        debugPrint('🔴 BESTIE CALL SIGNAL BACKLOG FAILED: $e');
      }
    }
  }

  Future<Map<String, dynamic>?> getCallSession(String callId) async {
    if (callId.isEmpty) return null;
    try {
      final row = await client
          .from('call_sessions')
          .select('id,caller_id,receiver_id,status,created_at,accepted_at,ended_at')
          .eq('id', callId)
          .maybeSingle();
      return row == null ? null : Map<String, dynamic>.from(row);
    } catch (e) {
      debugPrint('🔴 BESTIE CALL session read failed call=$callId: $e');
      return null;
    }
  }

  Stream<Map<String, dynamic>?> callSessionStream(String callId) {
    return client
        .from('call_sessions')
        .stream(primaryKey: ['id'])
        .eq('id', callId)
        .map((rows) => rows.isEmpty ? null : Map<String, dynamic>.from(rows.first));
  }

  Future<bool> acceptCall(String callId) async {
    final userId = _userId;
    if (userId == null) return false;

    final rows = await client
        .from('call_sessions')
        .update({
          'status': 'accepted',
          'accepted_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', callId)
        .eq('receiver_id', userId)
        .eq('status', 'ringing')
        .select('id,status');

    return rows.isNotEmpty;
  }

  Future<bool> rejectCallSession(String callId) async {
    final userId = _userId;
    if (userId == null) return false;
    final rows = await client
        .from('call_sessions')
        .update({'status': 'rejected', 'ended_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', callId)
        .eq('receiver_id', userId)
        .eq('status', 'ringing')
        .select('id,status');
    return rows.isNotEmpty;
  }

  Future<bool> endCallSession(String callId) async {
    final userId = _userId;
    if (userId == null) return false;
    // RLS already limits this update to call participants. Do not restrict the
    // transition to caller_id: after a call is accepted either participant can
    // hang up, exactly like a normal two-way call.
    final rows = await client
        .from('call_sessions')
        .update({
          'status': 'ended',
          'ended_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', callId)
        .inFilter('status', ['ringing', 'accepted'])
        .select('id,status');
    return rows.isNotEmpty;
  }

  /// Terminates a call through both transports, with the realtime signal sent
  /// first so the other device leaves the call UI immediately. The durable DB
  /// transition follows and is authoritative for recovery/history.
  Future<bool> terminateCall(String callId) async {
    final userId = _userId;
    final partnerId = _partnerId;
    if (userId == null || partnerId == null || callId.isEmpty) return false;

    var signalSent = false;
    try {
      await send(type: 'hangup', callId: callId);
      signalSent = true;
    } catch (e) {
      debugPrint('BESTIE CALL terminate signal failed: $e');
    }

    var sessionEnded = false;
    try {
      sessionEnded = await endCallSession(callId);
    } catch (e) {
      debugPrint('BESTIE CALL terminate session update failed: $e');
    }

    // If the realtime signal was unavailable, the durable session watcher and
    // call-end push still give the other device a recovery path.
    try {
      await sendCallEndNotification(callId);
    } catch (e) {
      debugPrint('BESTIE CALL terminate push failed: $e');
    }

    return signalSent || sessionEnded;
  }

  void _emitSignal(Map<String, dynamic> row) {
    final rowId = row['id']?.toString();
    if (rowId != null && !_deliveredSignalIds.add(rowId)) return;
    final signal = CallSignal.fromPayload(row);
    if (signal.callId.isEmpty || signal.toUserId != _userId) return;
    debugPrint('📥 BESTIE CALL SIGNAL type=${signal.type} call=${signal.callId}');
    if (!_signals.isClosed) _signals.add(signal);
  }


  Future<String> createCall() async {
    final userId = _userId;
    final partnerId = _partnerId;
    if (userId == null || partnerId == null) {
      throw StateError('CallService is not connected to a pair.');
    }

    // Call creation is serialized in Postgres. The old Dart read-then-insert
    // flow could race when two taps/devices started a call together and create
    // two ringing sessions. start_call() takes a transaction advisory lock for
    // this exact pair and is therefore the single source of truth.
    try {
      final result = await client.rpc(
        'start_call',
        params: {'p_receiver_id': partnerId},
      );
      final callId = result?.toString() ?? '';
      if (callId.isEmpty) throw StateError('start_call returned an empty call id.');

      // Reused ringing calls do not need another push. We can determine this
      // from the session row after the RPC without reopening the race window.
      final session = await getCallSession(callId);
      final isFresh = session?['caller_id']?.toString() == userId &&
          session?['status']?.toString() == 'ringing' &&
          session?['created_at'] != null &&
          DateTime.tryParse(session!['created_at'].toString())
                  ?.isAfter(DateTime.now().toUtc().subtract(const Duration(seconds: 3))) ==
              true;
      if (isFresh) {
        final delivered = await _sendCallNotification(
          callerId: userId,
          receiverId: partnerId,
          callId: callId,
        );
        if (!delivered) debugPrint('🔴 BESTIE CALL push delivery failed call=$callId');
      }
      return callId;
    } on PostgrestException catch (e) {
      final message = e.message.toUpperCase();
      if (message.contains('CALL_ALREADY_CONNECTED')) {
        throw StateError('A call with this partner is already connected.');
      }
      if (message.contains('PARTNER_CALL_IN_PROGRESS')) {
        throw StateError('This partner is already receiving or making a call.');
      }
      if (message.contains('INVALID_RECEIVER')) {
        throw StateError('Invalid call recipient.');
      }
      debugPrint('BESTIE CALL start_call RPC failed: ${e.message}');
      rethrow;
    }
  }

  Future<bool> _sendCallNotification({
    required String callerId,
    required String receiverId,
    required String callId,
  }) async {
    try {
      final caller = await client
          .from('profiles')
          .select('username')
          .eq('id', callerId)
          .maybeSingle();
      final callerName = (caller?['username'] ?? 'Partner').toString();
      return await NotificationService(client).create(
        userId: receiverId,
        title: callerName,
        body: 'Incoming call 📞',
        type: 'call',
        data: {
          'call_id': callId,
          'caller_id': callerId,
          'caller_name': callerName,
          'action': 'incoming_call',
          'event_key': 'call:$callId',
        },
      );
    } catch (e) {
      debugPrint('Call notification skipped: $e');
      return false;
    }
  }

  Future<void> sendCallEndNotification(String callId) async {
    final userId = _userId;
    final partnerId = _partnerId;
    if (userId == null || partnerId == null) return;
    try {
      await NotificationService(client).create(
        userId: partnerId,
        title: 'Call ended',
        body: 'The Bestie call has ended.',
        type: 'call_end',
        data: {
          'call_id': callId,
          'caller_id': userId,
          'action': 'call_ended',
          'event_key': 'call_end:$callId',
        },
      );
    } catch (e) {
      debugPrint('BESTIE CALL end push skipped: $e');
    }
  }

  Future<void> send({required String type, required String callId, Map<String, dynamic> data = const {}}) async {
    final userId = _userId;
    final partnerId = _partnerId;
    if (userId == null || partnerId == null) throw StateError('CallService is not connected.');
    final payload = CallSignal(
      type: type,
      callId: callId,
      fromUserId: userId,
      toUserId: partnerId,
      data: data,
    );
    await client.from('call_signals').insert(payload.toPayload());
  }

  Future<void> rejectCall(String callId) async {
    var signalSent = false;
    try {
      await send(type: 'reject', callId: callId);
      signalSent = true;
    } catch (e) {
      debugPrint('BESTIE CALL reject signal failed: $e');
    }
    final changed = await rejectCallSession(callId);
    if (changed || signalSent) {
      try {
        await sendCallEndNotification(callId);
      } catch (_) {}
    }
  }

  Future<void> disconnect() async {
    final channel = _signalChannel;
    _signalChannel = null;
    _userId = null;
    _partnerId = null;
    _deliveredSignalIds.clear();
    if (channel != null) await client.removeChannel(channel);
  }

  Future<void> dispose() async {
    await disconnect();
    await _signals.close();
  }
}
