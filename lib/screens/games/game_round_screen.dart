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

String _predictionLabel(String language, String choice) {
  const labels = <String, Map<String, String>>{
    'both': {
      'tr': 'İkimiz de',
      'en': 'Both of us',
      'de': 'Wir beide',
      'es': 'Ambos',
      'fr': 'Nous deux',
    },
    'neither': {
      'tr': 'Hiçbirimiz',
      'en': 'Neither of us',
      'de': 'Keiner von uns',
      'es': 'Ninguno de los dos',
      'fr': 'Aucun de nous deux',
    },
  };
  final locale = const {'tr', 'en', 'de', 'es', 'fr'}.contains(language)
      ? language
      : 'en';
  return labels[choice]?[locale] ?? labels[choice]?['en'] ?? choice;
}

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
    final languageCode = AppStrings.of(context).code;
    final client = Supabase.instance.client;

    return ChangeNotifierProvider(
      create: (_) => GameRoundProvider(
        roundService: GameRoundService(
          client,
          languageCode: languageCode,
        ),
        sessionService: GameSessionService(client),
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
              '${appBarConfig.emoji} ${appBarConfig.title} Â· Round ${provider.roundNumber}',
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
              FilledButton(onPressed: provider.retry, child: Text(AppStrings.of(context).t('retry_game'))),
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
          'Round ${provider.roundNumber} Â· ${question.category}',
          style: Theme.of(context).textTheme.labelMedium,
          textAlign: TextAlign.center,
        ),
        if (question.subcategory != null) ...[
          const SizedBox(height: 4),
          Text(question.subcategory!, textAlign: TextAlign.center),
        ],
        const SizedBox(height: 24),
        if (question.questionType == 'prediction')
          const _QuestionModeBadge(label: 'ğŸ’­ Partnerinin cevabÄ±nÄ± tahmin et')
        else if (question.questionType == 'choice')
          const _QuestionModeBadge(label: 'âœ¨ Bir seÃ§enek seÃ§')
        else if (question.questionType == 'word')
          const _QuestionModeBadge(label: 'ğŸ”¤ Kelimeyi bul')
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
          if (question.questionType == 'prediction')
            ...[
              ...provider.players.map(
                (player) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _AnswerButton(
                    label: player.userId == provider.currentUserId
                        ? AppStrings.of(context).t('you')
                        : AppStrings.of(context).t('partner'),
                    selected: provider.currentUserAnswer?.answer == player.userId,
                    enabled: !answered,
                    onPressed: () => provider.submitAnswer(player.userId),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AnswerButton(
                  label: _predictionLabel(AppStrings.of(context).code, 'both'),
                  selected: provider.currentUserAnswer?.answer == 'both_of_us',
                  enabled: !answered,
                  onPressed: () => provider.submitAnswer('both_of_us'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AnswerButton(
                  label: _predictionLabel(AppStrings.of(context).code, 'neither'),
                  selected: provider.currentUserAnswer?.answer == 'neither_of_us',
                  enabled: !answered,
                  onPressed: () => provider.submitAnswer('neither_of_us'),
                ),
              ),
            ]
          else if (question.options.isNotEmpty)
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
              decoration: InputDecoration(
                labelText: AppStrings.of(context).t('your_answer'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: answered || provider.isSubmitting
                  ? null
                  : () => provider.submitAnswer(_answerController.text),
              child: provider.isSubmitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator())
                  : Text(AppStrings.of(context).t('submit_answer')),
            ),
          ],
          const SizedBox(height: 24),
          if (answered && !bothAnswered)
            _WaitingCard(
              title: '${AppStrings.of(context).t('your_answer')} âœ“',
              message: config.waitingMessage,
            ),
          if (bothAnswered && !resolved)
            _WaitingCard(
              title: AppStrings.of(context).t('both_answered'),
              message: AppStrings.of(context).t('results_preparing'),
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
        Text(AppStrings.of(context).t('round_complete'), style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 18),
        if (myResult != null)
          _ResultCard(
            title: AppStrings.of(context).t('you'),
            result: myResult,
            gameType: provider.question?.gameType,
            questionType: provider.question?.questionType,
            answerLabel: _formatAnswerLabel(context, provider, myResult.answer),
          ),
        if (partnerResult != null)
          _ResultCard(
            title: AppStrings.of(context).t('partner'),
            result: partnerResult,
            gameType: provider.question?.gameType,
            questionType: provider.question?.questionType,
            answerLabel: _formatAnswerLabel(context, provider, partnerResult.answer),
          ),
        const SizedBox(height: 12),
        if (provider.gameCompleted)
          FilledButton(
            onPressed: () => context.go('/home/games'),
            child: Text(AppStrings.of(context).t('finish_game')),
          )
        else if (provider.currentRoundConfirmed)
          _WaitingCard(
            title: 'âœ“ ${AppStrings.of(context).t('next_round')}',
            message: 'Partnerinin de onaylamasÄ± bekleniyor.',
          )
        else
          FilledButton(
            onPressed: provider.isAdvancing ? null : provider.advanceToNextRound,
            child: provider.isAdvancing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator())
                : Text(AppStrings.of(context).t('next_round')),
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

String _formatAnswerLabel(
  BuildContext context,
  GameRoundProvider provider,
  String answer,
) {
  final language = AppStrings.of(context).code;
  if (answer == 'both_of_us') return _predictionLabel(language, 'both');
  if (answer == 'neither_of_us') return _predictionLabel(language, 'neither');
  if (provider.question?.questionType == 'prediction' &&
      provider.players.any((player) => player.userId == answer)) {
    return answer == provider.currentUserId
        ? AppStrings.of(context).t('you')
        : AppStrings.of(context).t('partner');
  }
  return answer;
}

class _ResultCard extends StatelessWidget {
  final String title;
  final GameRoundResult result;
  final String? gameType;
  final String? questionType;
  final String answerLabel;

  const _ResultCard({
    required this.title,
    required this.result,
    required this.gameType,
    required this.questionType,
    required this.answerLabel,
  });

  @override
  Widget build(BuildContext context) {
    final correct = result.isCorrect;
    final strings = AppStrings.of(context);
    final String status;
    if (gameType == 'most_likely_to' && questionType == 'prediction') {
      status = correct == null
          ? strings.t('prediction')
          : (correct ? strings.t('prediction_hit') : strings.t('prediction_miss'));
    } else if (gameType == 'most_likely_to' && questionType == 'choice') {
      status = correct == null
          ? strings.t('selection')
          : (correct ? strings.t('same_selection') : strings.t('different_selection'));
    } else {
      status = correct == null
          ? strings.t('answer_result')
          : (correct ? strings.t('correct') : strings.t('wrong'));
    }
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(answerLabel),
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

