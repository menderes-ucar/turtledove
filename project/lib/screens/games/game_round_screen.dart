import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/game_round_result_model.dart';
import '../../providers/game_round_provider.dart';
import '../../services/game_round_service.dart';
import '../../services/game_session_service.dart';
import '../../utils/game_type_config.dart';
import '../../localization/app_strings.dart';

class GameRoundScreen extends StatelessWidget {
  final String sessionId;
  final int roundNumber;

  const GameRoundScreen({
    required this.sessionId,
    required this.roundNumber,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => GameRoundProvider(
        roundService: GameRoundService(Supabase.instance.client),
        sessionService: GameSessionService(Supabase.instance.client),
        sessionId: sessionId,
        initialRoundNumber: roundNumber,
      ),
      child: const _GameRoundBody(),
    );
  }
}

class _GameRoundBody extends StatefulWidget {
  const _GameRoundBody();

  @override
  State<_GameRoundBody> createState() => _GameRoundBodyState();
}

class _GameRoundBodyState extends State<_GameRoundBody> {
  final TextEditingController _answerController = TextEditingController();
  bool _navigating = false;

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  void _navigateToNext(GameRoundProvider provider) {
    final next = provider.nextRoundNumber;
    if (next == null || _navigating || !mounted) return;
    _navigating = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go('/home/game-round/${provider.currentSessionId}/$next');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameRoundProvider>(
      builder: (context, provider, _) {
        if (provider.nextRoundNumber != null) {
          _navigateToNext(provider);
        }

        final appBarConfig = GameTypeConfig.forType(
          provider.question?.gameType ?? 'unknown',
          locale: AppStrings.of(context).code,
        );
        return Scaffold(
          appBar: AppBar(
            title: Text(
              '${appBarConfig.emoji} ${appBarConfig.title} · Round ${provider.roundNumber}',
            ),
          ),
          body: _buildBody(context, provider),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, GameRoundProvider provider) {
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.error != null && provider.question == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(provider.error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: provider.retry, child: const Text('Tekrar dene')),
            ],
          ),
        ),
      );
    }

    final question = provider.question!;
    final config = GameTypeConfig.forType(question.gameType, locale: AppStrings.of(context).code);
    final answered = provider.hasCurrentUserAnswer;
    final bothAnswered = provider.bothPlayersAnswered;
    final resolved = provider.roundResolved;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          '${config.emoji} ${config.title}',
          style: Theme.of(context).textTheme.labelLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Round ${provider.roundNumber} · ${question.category}',
          style: Theme.of(context).textTheme.labelMedium,
          textAlign: TextAlign.center,
        ),
        if (question.subcategory != null) ...[
          const SizedBox(height: 4),
          Text(question.subcategory!, textAlign: TextAlign.center),
        ],
        const SizedBox(height: 24),
        if (question.questionType == 'prediction')
          const _QuestionModeBadge(label: '💭 Partnerinin cevabını tahmin et')
        else if (question.questionType == 'choice')
          const _QuestionModeBadge(label: '✨ Bir seçenek seç')
        else if (question.questionType == 'word')
          const _QuestionModeBadge(label: '🔤 Kelimeyi bul')
        else
          _QuestionModeBadge(label: config.answerHint),
        const SizedBox(height: 14),
        Text(
          question.prompt,
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (!resolved) ...[
          if (question.options.isNotEmpty)
            ...question.options.map(
              (option) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AnswerButton(
                  label: option,
                  selected: provider.currentUserAnswer?.answer == option,
                  enabled: !answered,
                  onPressed: () => provider.submitAnswer(option),
                ),
              ),
            )
          else ...[
            TextField(
              controller: _answerController,
              enabled: !answered,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Cevabın',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: answered || provider.isSubmitting
                  ? null
                  : () => provider.submitAnswer(_answerController.text),
              child: provider.isSubmitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator())
                  : const Text('Cevabı gönder'),
            ),
          ],
          const SizedBox(height: 24),
          if (answered && !bothAnswered)
            _WaitingCard(
              title: 'Cevabın kaydedildi ✓',
              message: config.waitingMessage,
            ),
          if (bothAnswered && !resolved)
            const _WaitingCard(
              title: 'İkiniz de cevapladınız',
              message: 'Sonuç hazırlanıyor...',
            ),
        ],
        if (resolved) _buildResult(context, provider),
        if (provider.error != null) ...[
          const SizedBox(height: 12),
          Text(provider.error!, textAlign: TextAlign.center),
        ],
      ],
    );
  }

  Widget _buildResult(BuildContext context, GameRoundProvider provider) {
    final results = provider.results;
    final currentId = provider.currentUserId;
    GameRoundResult? myResult;
    GameRoundResult? partnerResult;
    for (final result in results) {
      if (result.userId == currentId) {
        myResult = result;
      } else {
        partnerResult ??= result;
      }
    }

    return Column(
      children: [
        const Icon(Icons.celebration_outlined, size: 54),
        const SizedBox(height: 10),
        Text('Round tamamlandı 🎉', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 18),
        if (myResult != null)
          _ResultCard(
            title: 'Sen',
            result: myResult,
            gameType: provider.question?.gameType,
            questionType: provider.question?.questionType,
          ),
        if (partnerResult != null)
          _ResultCard(
            title: 'Partnerin',
            result: partnerResult,
            gameType: provider.question?.gameType,
            questionType: provider.question?.questionType,
          ),
        const SizedBox(height: 12),
        if (provider.gameCompleted)
          FilledButton(
            onPressed: () => context.go('/home/games'),
            child: const Text('Oyunu bitir'),
          )
        else
          FilledButton(
            onPressed: provider.isAdvancing ? null : provider.advanceToNextRound,
            child: provider.isAdvancing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator())
                : const Text('Sonraki round →'),
          ),
      ],
    );
  }
}

class _QuestionModeBadge extends StatelessWidget {
  final String label;

  const _QuestionModeBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Text(label),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final String title;
  final GameRoundResult result;
  final String? gameType;
  final String? questionType;

  const _ResultCard({
    required this.title,
    required this.result,
    required this.gameType,
    required this.questionType,
  });

  @override
  Widget build(BuildContext context) {
    final correct = result.isCorrect;
    final String status;
    if (gameType == 'most_likely_to' && questionType == 'prediction') {
      status = correct == null ? 'Tahmin' : (correct ? 'Tahmin tuttu ✓' : 'Tutmadı');
    } else if (gameType == 'most_likely_to' && questionType == 'choice') {
      status = correct == null ? 'Seçim' : (correct ? 'Aynı seçim ✓' : 'Farklı seçim');
    } else {
      status = correct == null ? 'Cevap' : (correct ? 'Doğru ✓' : 'Yanlış');
    }
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(result.answer),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(status),
            if (result.points != 0) Text('+${result.points}'),
          ],
        ),
      ),
    );
  }
}

class _AnswerButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  const _AnswerButton({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            if (selected) const Icon(Icons.check_circle),
          ],
        ),
      ),
    );
  }
}

class _WaitingCard extends StatelessWidget {
  final String title;
  final String message;

  const _WaitingCard({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
