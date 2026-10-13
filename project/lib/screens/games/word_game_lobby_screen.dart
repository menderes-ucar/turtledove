import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/auth_provider.dart';
import '../../providers/word_game_provider.dart';
import '../../models/game_session_model.dart';
import '../../services/game_session_service.dart';
import '../../services/word_game_service.dart';
import 'word_game_round_screen.dart';
import 'word_game_localization.dart';

class WordGameLobbyScreen extends StatefulWidget {
  const WordGameLobbyScreen({super.key});

  @override
  State<WordGameLobbyScreen> createState() => _WordGameLobbyScreenState();
}

class _WordGameLobbyScreenState extends State<WordGameLobbyScreen> {
  String? _languageCode;
  bool _started = false;
  bool _checkingActiveSession = true;
  GameSession? _activeSession;

  static const languages = <Map<String, String>>[
    {'code': 'tr', 'name': 'Türkçe', 'flag': '🇹🇷'},
    {'code': 'en', 'name': 'English', 'flag': '🇬🇧'},
    {'code': 'de', 'name': 'Deutsch', 'flag': '🇩🇪'},
    {'code': 'es', 'name': 'Español', 'flag': '🇪🇸'},
    {'code': 'fr', 'name': 'Français', 'flag': '🇫🇷'},
  ];

  @override
  void initState() {
    super.initState();
    _loadActiveSession();
  }

  Future<void> _loadActiveSession() async {
    final partnerId = context.read<AuthProvider>().profile?.pairedWith;

    if (!_checkingActiveSession) {
      return;
    }

    if (partnerId == null || partnerId.isEmpty) {
      if (mounted) setState(() => _checkingActiveSession = false);
      return;
    }

    try {
      final session = await GameSessionService(Supabase.instance.client)
          .getActiveSession(gameType: 'word_game', partnerId: partnerId);
      if (!mounted) return;

      final language = session?.category?.trim().toLowerCase();
      if (session != null && language != null &&
          {'tr', 'en', 'de', 'es', 'fr'}.contains(language)) {
        setState(() {
          _activeSession = session;
          _languageCode = language;
          _started = true;
          _checkingActiveSession = false;
        });
        return;
      }

      setState(() {
        _activeSession = null;
        _checkingActiveSession = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checkingActiveSession = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final partnerId = context.read<AuthProvider>().profile?.pairedWith;
    if (partnerId == null || partnerId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(WordGameStrings.of(context).title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              WordGameStrings.of(context).beforePairing,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (!_started) return _buildLanguageSelection(context);

    return ChangeNotifierProvider(
      create: (_) => WordGameProvider(
        sessionService: GameSessionService(Supabase.instance.client),
        wordService: WordGameService(Supabase.instance.client),
        partnerId: partnerId,
        languageCode: _languageCode!,
        initialSession: _activeSession,
      ),
      child: const _WordGameLobbyBody(),
    );
  }

  Widget _buildLanguageSelection(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(WordGameStrings.of(context).title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(WordGameStrings.of(context).chooseLanguage, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(WordGameStrings.of(context).dictionaryInfo),
          const SizedBox(height: 20),
          ...languages.map(
            (language) => Card(
              child: RadioListTile<String>(
                value: language['code']!,
                groupValue: _languageCode,
                onChanged: (value) => setState(() => _languageCode = value),
                title: Text('${language['flag']} ${language['name']}'),
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _languageCode == null
                  ? null
                  : () => setState(() => _started = true),
              icon: const Icon(Icons.play_arrow),
              label: Text(WordGameStrings.of(context).play),
            ),
          ),
        ],
      ),
    );
  }
}

class _WordGameLobbyBody extends StatelessWidget {
  const _WordGameLobbyBody();

  @override
  Widget build(BuildContext context) {
    return Consumer<WordGameProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.session == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (provider.error != null && provider.session == null) {
          return Scaffold(
            appBar: AppBar(title: Text(WordGameStrings.of(context).title)),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(provider.error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: provider.retry, child: Text(WordGameStrings.of(context).retry)),
                  ],
                ),
              ),
            ),
          );
        }

        if (provider.state?.isPlaying == true) {
          return WordGameRoundScreen(sessionId: provider.session!.id);
        }

        final me = provider.currentPlayer;
        final partner = _findPartner(provider);

        return Scaffold(
          appBar: AppBar(title: Text(WordGameStrings.of(context).title)),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(WordGameStrings.of(context).sameGame, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('${WordGameStrings.of(context).language}: ${_languageName(provider.languageCode)}'),
              const SizedBox(height: 24),
              _PlayerCard(title: WordGameStrings.of(context).you, ready: me?.ready ?? false),
              const SizedBox(height: 12),
              _PlayerCard(title: WordGameStrings.of(context).partner, ready: partner?.ready ?? false),
              const SizedBox(height: 24),
              if (provider.bothPlayersReady)
                Text(WordGameStrings.of(context).bothReady, textAlign: TextAlign.center)
              else
                Text(
                  me?.ready == true ? WordGameStrings.of(context).waitingPartner : WordGameStrings.of(context).pressReady,
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: provider.isReadyLoading || provider.isStarting ? null : provider.toggleReady,
                icon: provider.isReadyLoading || provider.isStarting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator())
                    : Icon(me?.ready == true ? Icons.close : Icons.check),
                label: Text(me?.ready == true ? WordGameStrings.of(context).notReady : WordGameStrings.of(context).imReady),
              ),
              if (provider.error != null) ...[
                const SizedBox(height: 16),
                Text(provider.error!, textAlign: TextAlign.center),
              ],
            ],
          ),
        );
      },
    );
  }

  GamePlayer? _findPartner(WordGameProvider provider) {
    final currentId = provider.currentUserId;
    for (final player in provider.players) {
      if (player.userId != currentId) return player;
    }
    return null;
  }

  String _languageName(String code) {
    const names = {'tr': 'Türkçe 🇹🇷', 'en': 'English 🇬🇧', 'de': 'Deutsch 🇩🇪', 'es': 'Español 🇪🇸', 'fr': 'Français 🇫🇷'};
    return names[code] ?? code;
  }
}

class _PlayerCard extends StatelessWidget {
  final String title;
  final bool ready;
  const _PlayerCard({required this.title, required this.ready});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(ready ? Icons.check : Icons.person_outline)),
        title: Text(title),
        trailing: Text(ready ? '${WordGameStrings.of(context).ready} ✓' : WordGameStrings.of(context).waiting),
      ),
    );
  }
}
