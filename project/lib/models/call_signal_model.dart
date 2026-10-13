class CallSignal {
  final String? id;
  final String type;
  final String callId;
  final String fromUserId;
  final String toUserId;
  final Map<String, dynamic> data;

  const CallSignal({
    this.id,
    required this.type,
    required this.callId,
    required this.fromUserId,
    required this.toUserId,
    this.data = const {},
  });

  factory CallSignal.fromPayload(Map<String, dynamic> payload) {
    // call_signals is a Postgres table, so its column names are used here.
    // Keep the old from/to keys as a fallback so this model remains tolerant
    // of any legacy signal payloads.
    final rawData = payload['data'];
    return CallSignal(
      id: payload['id']?.toString(),
      type: payload['type']?.toString() ?? '',
      callId: payload['call_id']?.toString() ?? '',
      fromUserId: (payload['from_user_id'] ?? payload['from'])?.toString() ?? '',
      toUserId: (payload['to_user_id'] ?? payload['to'])?.toString() ?? '',
      data: rawData is Map
          ? Map<String, dynamic>.from(rawData)
          : const <String, dynamic>{},
    );
  }

  Map<String, dynamic> toPayload() => {
        'type': type,
        'call_id': callId,
        'from_user_id': fromUserId,
        'to_user_id': toUserId,
        'data': data,
      };
}
