import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../localization/app_strings.dart';
import '../../providers/auth_provider.dart';
import '../../services/notification_service.dart';

class TruthOrDareScreen extends StatefulWidget {
  const TruthOrDareScreen({super.key});

  @override
  State<TruthOrDareScreen> createState() => _TruthOrDareScreenState();
}

class _TruthOrDareScreenState extends State<TruthOrDareScreen> {
  final _client = Supabase.instance.client;
  RealtimeChannel? _channel;
  Map<String, dynamic>? _session;
  List<Map<String, dynamic>> _prompts = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _sessionId;

  String get _userId => _client.auth.currentUser!.id;
  String get _locale => AppStrings.of(context).code;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final partnerId = context.read<AuthProvider>().profile?.pairedWith;
    if (partnerId == null || partnerId.isEmpty) {
      setState(() { _loading = false; _error = 'partner_required'; });
      return;
    }
    try {
      final existing = await _client.rpc('bestie_get_active_truth_dare_v3', params: {'p_partner_id': partnerId});
      if (existing is List && existing.isNotEmpty) {
        _session = Map<String, dynamic>.from(existing.first as Map);
      } else if (existing is Map && existing.isNotEmpty) {
        _session = Map<String, dynamic>.from(existing);
      } else {
        final created = await _client.rpc('bestie_create_truth_dare_v3', params: {'p_partner_id': partnerId});
        _session = Map<String, dynamic>.from(created is List ? created.first : created);
        await _notifyPartner(partnerId);
      }
      _sessionId = _session!['id'].toString();
      await _loadPrompts();
      _listen();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPrompts() async {
    final rows = await _client.from('truth_or_dare_prompts').select().eq('is_active', true);
    _prompts = rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> _reloadSession() async {
    final id = _sessionId;
    if (id == null || id.isEmpty) return;
    try {
      final result = await _client.rpc(
        'bestie_truth_dare_state_v3',
        params: {'p_session_id': id},
      );
      final row = result is Map
          ? Map<String, dynamic>.from(result)
          : result is List && result.isNotEmpty && result.first is Map
              ? Map<String, dynamic>.from(result.first as Map)
              : null;
      if (row != null && mounted) setState(() => _session = row);
    } catch (e) { debugPrint('Truth or Dare state refresh skipped: $e'); }
  }

  void _listen() {
    final id = _sessionId;
    if (id == null) return;
    _channel = _client.channel('bestie-truth-dare-$id')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public', table: 'truth_or_dare_sessions',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: id),
        callback: (_) {
          unawaited(_reloadSession());
        },
      )
      ..subscribe();
  }

  String _prompt(Map<String, dynamic> row) =>
      (row['prompt_$_locale'] ?? row['prompt_en'] ?? row['prompt_tr'] ?? '').toString();

  Future<void> _notifyPartner(String partnerId) async {
    try {
      final row = await _client.from('profiles').select('language_code').eq('id', partnerId).maybeSingle();
      final l = {'tr','en','de','es','fr'}.contains(row?['language_code']) ? row!['language_code'].toString() : 'en';
      const titles = {'tr':'Doğruluk mu Cesaret mi? 🔥','en':'Truth or Dare 🔥','de':'Wahrheit oder Pflicht 🔥','es':'Verdad o reto 🔥','fr':'Action ou vérité 🔥'};
      const bodies = {'tr':'Partnerin seninle oynamak için yeni bir oyun başlattı.','en':'Your partner started a new game with you.','de':'Dein Partner hat ein neues Spiel mit dir gestartet.','es':'Tu pareja ha iniciado un nuevo juego contigo.','fr':'Votre partenaire a commencé une nouvelle partie avec vous.'};
      await NotificationService(_client).create(userId: partnerId, title: titles[l]!, body: bodies[l]!, type: 'game', data: {'game_type':'truth_or_dare','action':'open_game','event_key':'truth_or_dare:$_sessionId'});
    } catch (e) { debugPrint('Truth or Dare notification skipped: $e'); }
  }


  Future<void> _choose(String mode) async {
    if (_busy || _session == null) return;
    setState(() => _busy = true);
    try {
      final used = Set<String>.from(List<String>.from(_session!['used_prompt_ids'] ?? const []));
      final candidates = _prompts.where((p) => p['mode'] == mode && !used.contains(p['id'].toString())).toList();
      if (candidates.isEmpty) throw StateError('No more prompts in this category.');
      final selected = candidates[Random().nextInt(candidates.length)];
      final result = await _client.rpc('bestie_start_truth_dare_round_v3', params: {
        'p_session_id': _session!['id'],
        'p_mode': mode,
        'p_prompt_id': selected['id'],
      });
      _session = Map<String, dynamic>.from(result is List ? result.first : result);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete() async {
    if (_busy || _session == null) return;
    setState(() => _busy = true);
    try {
      final result = await _client.rpc('bestie_complete_truth_dare_round_v3', params: {'p_session_id': _session!['id']});
      _session = Map<String, dynamic>.from(result is List ? result.first : result);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    if (_channel != null) unawaited(_client.removeChannel(_channel!));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null && _session == null) {
      return Scaffold(appBar: AppBar(title: Text(s.gameTruthDare)), body: Center(child: Text(_error == 'partner_required' ? s.gamePartnerRequired : _error!)));
    }
    final session = _session!;
    final completed = session['status'] == 'completed';
    final turn = session['turn_user_id']?.toString() == _userId;
    final promptMap = session['current_prompt'] is Map ? Map<String, dynamic>.from(session['current_prompt']) : null;
    final mode = session['current_mode']?.toString();
    final round = (session['current_round'] as num?)?.toInt() ?? 1;

    return Scaffold(
      appBar: AppBar(title: Text('${s.gameTruthDare} · $round/15')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _HeaderCard(round: round, completed: completed, turn: turn, title: s.gameTruthDare, subtitle: completed ? s.gameCompleted : turn ? s.truthDareYourTurn : s.truthDarePartnerTurn),
          const SizedBox(height: 20),
          if (!completed && promptMap == null && turn) ...[
            _ChoiceCard(emoji: '🗣️', title: s.truth, subtitle: s.truthSubtitle, onTap: _busy ? null : () => _choose('truth')),
            const SizedBox(height: 12),
            _ChoiceCard(emoji: '🔥', title: s.dare, subtitle: s.dareSubtitle, onTap: _busy ? null : () => _choose('dare')),
          ] else if (!completed && promptMap == null) ...[
            Center(child: Padding(padding: const EdgeInsets.all(30), child: Text(s.truthDareWaiting, textAlign: TextAlign.center))),
          ] else if (!completed && promptMap != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  Text(mode == 'truth' ? '🗣️ ${s.truth}' : '🔥 ${s.dare}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 20),
                  Text(_prompt(promptMap), textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 28),
                  if (turn) FilledButton.icon(onPressed: _busy ? null : _complete, icon: const Icon(Icons.check_rounded), label: Text(s.truthDareDone))
                  else Text(s.truthDareWaiting, textAlign: TextAlign.center),
                ]),
              ),
            ),
          ] else ...[
            Center(child: Padding(padding: const EdgeInsets.all(30), child: Column(children: [const Text('🎉', style: TextStyle(fontSize: 64)), const SizedBox(height: 12), Text(s.gameCompleted, style: Theme.of(context).textTheme.headlineSmall)]))),
          ],
          if (_error != null) ...[const SizedBox(height: 16), Text(_error!, textAlign: TextAlign.center)],
          const SizedBox(height: 12),
          TextButton(onPressed: () => context.pop(), child: Text(s.close)),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final int round; final bool completed; final bool turn; final String title; final String subtitle;
  const _HeaderCard({required this.round, required this.completed, required this.turn, required this.title, required this.subtitle});
  @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(20), child: Row(children: [const Text('🎲', style: TextStyle(fontSize: 40)), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)), const SizedBox(height: 5), Text(subtitle), if (!completed) ...[const SizedBox(height: 10), LinearProgressIndicator(value: round / 15)]]))])));
}

class _ChoiceCard extends StatelessWidget {
  final String emoji, title, subtitle; final VoidCallback? onTap;
  const _ChoiceCard({required this.emoji, required this.title, required this.subtitle, required this.onTap});
  @override Widget build(BuildContext context) => Card(child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: Padding(padding: const EdgeInsets.all(20), child: Row(children: [Text(emoji, style: const TextStyle(fontSize: 38)), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)), const SizedBox(height: 5), Text(subtitle)])), const Icon(Icons.arrow_forward_rounded)]))));
}
