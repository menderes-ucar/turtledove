import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../localization/app_strings.dart';

class VoiceMessageArchiveScreen extends StatefulWidget {
  final String partnerId;
  const VoiceMessageArchiveScreen({super.key, required this.partnerId});

  @override
  State<VoiceMessageArchiveScreen> createState() => _VoiceMessageArchiveScreenState();
}

class _VoiceMessageArchiveScreenState extends State<VoiceMessageArchiveScreen> {
  late Future<List<Map<String, dynamic>>> _messagesFuture;

  @override
  void initState() {
    super.initState();
    _messagesFuture = _loadMessages();
  }

  Future<List<Map<String, dynamic>>> _loadMessages() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('Sign in to view voice messages.');

    final rows = await client
        .from('messages')
        .select('id,sender_id,receiver_id,media_url,content,created_at')
        .or('and(sender_id.eq.$userId,receiver_id.eq.${widget.partnerId}),and(sender_id.eq.${widget.partnerId},receiver_id.eq.$userId)')
        .not('media_url', 'is', null)
        .order('created_at', ascending: false);

    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .where((row) => _isAudioUrl(row['media_url']?.toString() ?? ''))
        .toList(growable: false);
  }

  bool _isAudioUrl(String value) {
    final path = Uri.tryParse(value)?.path.toLowerCase() ?? value.toLowerCase();
    return RegExp(r'\.(m4a|mp3|aac|wav|ogg|opus|caf|3gp|amr)$').hasMatch(path);
  }

  void _reload() => setState(() => _messagesFuture = _loadMessages());

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.t('voice_archive_title')),
        actions: [IconButton(onPressed: _reload, tooltip: strings.t('refresh'), icon: const Icon(Icons.refresh_rounded))],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _messagesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off_rounded, size: 42),
                  const SizedBox(height: 12),
                  Text(strings.t('voice_archive_load_failed'), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh), label: Text(strings.t('retry'))),
                ]),
              ),
            );
          }
          final messages = snapshot.data ?? const <Map<String, dynamic>>[];
          if (messages.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.mic_none_rounded, size: 64, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 14),
                  Text(strings.t('voice_archive_empty_title'), style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(strings.t('voice_archive_empty_subtitle'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                ]),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final message = messages[index];
              final userId = Supabase.instance.client.auth.currentUser?.id;
              final mine = message['sender_id']?.toString() == userId;
              final date = DateTime.tryParse(message['created_at']?.toString() ?? '')?.toLocal();
              return Card(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(mine ? Icons.call_made_rounded : Icons.call_received_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(mine ? strings.t('voice_archive_sent') : strings.t('voice_archive_received'), style: Theme.of(context).textTheme.labelLarge)),
                      if (date != null) Text(MaterialLocalizations.of(context).formatShortDate(date), style: Theme.of(context).textTheme.labelSmall),
                    ]),
                    const SizedBox(height: 6),
                    _VoiceArchivePlayer(url: message['media_url'].toString()),
                    if ((message['content']?.toString().trim().isNotEmpty ?? false)) ...[
                      const SizedBox(height: 6),
                      Text(message['content'].toString()),
                    ],
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _VoiceArchivePlayer extends StatefulWidget {
  final String url;
  const _VoiceArchivePlayer({required this.url});

  @override
  State<_VoiceArchivePlayer> createState() => _VoiceArchivePlayerState();
}

class _VoiceArchivePlayerState extends State<_VoiceArchivePlayer> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<void>? _completeSubscription;
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  PlayerState _state = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _stateSubscription = _player.onPlayerStateChanged.listen((value) { if (mounted) setState(() => _state = value); });
    _durationSubscription = _player.onDurationChanged.listen((value) { if (mounted) setState(() => _duration = value); });
    _positionSubscription = _player.onPositionChanged.listen((value) { if (mounted) setState(() => _position = value); });
    _completeSubscription = _player.onPlayerComplete.listen((_) { if (mounted) setState(() => _position = _duration); });
  }

  @override
  void dispose() {
    _completeSubscription?.cancel();
    _stateSubscription?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      setState(() => _failed = false);
      if (_state == PlayerState.playing) {
        await _player.pause();
      } else if (_position >= _duration && _duration > Duration.zero) {
        await _player.seek(Duration.zero);
        await _player.play(UrlSource(widget.url));
      } else if (_state == PlayerState.paused) {
        await _player.resume();
      } else {
        await _player.play(UrlSource(widget.url));
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  String _time(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final maxMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1.0;
    return Row(children: [
      IconButton.filledTonal(
        onPressed: _toggle,
        tooltip: _state == PlayerState.playing ? strings.pauseAudio : strings.playAudio,
        icon: Icon(_state == PlayerState.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
      ),
      Expanded(child: Slider(
        value: _position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble(),
        max: maxMs,
        onChanged: _duration == Duration.zero ? null : (value) => _player.seek(Duration(milliseconds: value.round())),
      )),
      Text(_time(_state == PlayerState.playing || _state == PlayerState.paused ? _position : _duration), style: Theme.of(context).textTheme.labelSmall),
      if (_failed) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.error_outline_rounded, color: Colors.red, size: 18)),
    ]);
  }
}
