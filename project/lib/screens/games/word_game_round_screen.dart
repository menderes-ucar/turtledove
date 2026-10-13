import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/word_game_provider.dart';
import '../../models/game_session_model.dart';
import 'word_game_localization.dart';

class WordGameRoundScreen extends StatefulWidget {
  final String sessionId;
  const WordGameRoundScreen({required this.sessionId, super.key});

  @override
  State<WordGameRoundScreen> createState() => _WordGameRoundScreenState();
}

class _WordGameRoundScreenState extends State<WordGameRoundScreen> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WordGameProvider>(
      builder: (context, provider, _) {
        final state = provider.state;
        if (state == null) {
          return Scaffold(
            appBar: AppBar(title: Text(WordGameStrings.of(context).title)),
            body: provider.error == null
                ? const Center(child: CircularProgressIndicator())
                : Center(child: Text(provider.error!, textAlign: TextAlign.center)),
          );
        }

        if (state.isCompleted) return _completed(context, provider);

        final canPlay = provider.myTurn && !provider.isSubmitting;

        return Scaffold(
          appBar: AppBar(
            title: Text('🔤 ${_languageName(state.languageCode)}'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(child: Text('${WordGameStrings.of(context).round} ${state.turnNumber}')),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _TurnHeader(
                myTurn: provider.myTurn,
                requiredLetter: state.requiredLetter,
              ),
              const SizedBox(height: 14),
              _MistakeRow(
                players: provider.players,
                currentUserId: provider.currentUserId,
              ),
              const SizedBox(height: 18),
              if (state.lastWord != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Text(WordGameStrings.of(context).lastWord, style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(state.lastWord!, style: Theme.of(context).textTheme.headlineMedium),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              TextField(
                controller: _controller,
                enabled: canPlay,
                textCapitalization: TextCapitalization.words,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: WordGameStrings.of(context).startsWith(state.requiredLetter.toUpperCase()),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: canPlay ? (_) => _submit(provider) : null,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: canPlay ? () => _submit(provider) : null,
                icon: provider.isSubmitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator())
                    : const Icon(Icons.send),
                label: Text(WordGameStrings.of(context).submit),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: provider.myTurn ? () => _confirmSurrender(context, provider) : null,
                icon: const Icon(Icons.flag_outlined),
                label: Text(WordGameStrings.of(context).surrender),
              ),
              const SizedBox(height: 24),
              Text(
                provider.myTurn
                    ? WordGameStrings.of(context).myTurn
                    : WordGameStrings.of(context).partnerTurn,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Text(WordGameStrings.of(context).history, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ...provider.plays.reversed.map(
                (play) => ListTile(
                  dense: true,
                  leading: CircleAvatar(child: Text(play.points.toString())),
                  title: Text(play.word),
                  subtitle: Text('${WordGameStrings.of(context).round} ${play.turnNumber}'),
                ),
              ),
              if (provider.error != null) ...[
                const SizedBox(height: 12),
                Text(provider.error!, textAlign: TextAlign.center),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _submit(WordGameProvider provider) async {
    final word = _controller.text.trim();
    if (word.isEmpty) return;
    await provider.submitWord(word);
    if (!mounted) return;
    if (provider.error == null) _controller.clear();
  }

  Future<void> _confirmSurrender(BuildContext context, WordGameProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(WordGameStrings.of(context).surrenderQuestion),
        content: Text(WordGameStrings.of(context).surrenderInfo),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(WordGameStrings.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(WordGameStrings.of(context).surrender),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await provider.surrender();
    }
  }

  String stateResultTitle(WordGameProvider provider) {
    final state = provider.state;
    final me = provider.currentUserId;
    if (state?.winnerUserId == me) return WordGameStrings.of(context).won;
    if (state?.loserUserId == me) return WordGameStrings.of(context).lost;
    return WordGameStrings.of(context).gameOver;
  }

  String _endReasonText(String? reason) {
    switch (reason) {
      case 'surrender':
        return WordGameStrings.of(context).reason('surrender');
      case 'three_mistakes':
        return WordGameStrings.of(context).reason('three_mistakes');
      default:
        return WordGameStrings.of(context).reason(null);
    }
  }

  Widget _completed(BuildContext context, WordGameProvider provider) {
    return Scaffold(
      appBar: AppBar(title: Text(WordGameStrings.of(context).completed)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.emoji_events_outlined, size: 72),
              const SizedBox(height: 16),
              Text(WordGameStrings.of(context).chainComplete, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 10),
              Text(WordGameStrings.of(context).played(provider.plays.length)),
              const SizedBox(height: 24),
              FilledButton(onPressed: () => context.go('/home'), child: Text(WordGameStrings.of(context).home)),
            ],
          ),
        ),
      ),
    );
  }

  String _languageName(String code) {
    const names = {'tr': 'Türkçe', 'en': 'English', 'de': 'Deutsch', 'es': 'Español', 'fr': 'Français'};
    return names[code] ?? code.toUpperCase();
  }
}

class _MistakeRow extends StatelessWidget {
  final List<GamePlayer> players;
  final String? currentUserId;

  const _MistakeRow({
    required this.players,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    GamePlayer? me;
    GamePlayer? partner;
    for (final player in players) {
      if (player.userId == currentUserId) {
        me = player;
      } else {
        partner ??= player;
      }
    }

    return Row(
      children: [
        Expanded(child: _MistakeCard(label: WordGameStrings.of(context).you, mistakes: me?.mistakes ?? 0)),
        const SizedBox(width: 10),
        Expanded(child: _MistakeCard(label: WordGameStrings.of(context).partner, mistakes: partner?.mistakes ?? 0)),
      ],
    );
  }
}

class _MistakeCard extends StatelessWidget {
  final String label;
  final int mistakes;

  const _MistakeCard({required this.label, required this.mistakes});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        child: Column(
          children: [
            Text(label),
            const SizedBox(height: 4),
            Text('$mistakes/3 ${WordGameStrings.of(context).mistakes}', style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _TurnHeader extends StatelessWidget {
  final bool myTurn;
  final String requiredLetter;
  const _TurnHeader({required this.myTurn, required this.requiredLetter});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(myTurn ? WordGameStrings.of(context).myTurn : WordGameStrings.of(context).partnerTurn, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            Text(requiredLetter.toUpperCase(), style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(height: 4),
            Text(WordGameStrings.of(context).typeWord),
          ],
        ),
      ),
    );
  }
}
