
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/game_category_model.dart';
import '../../models/game_session_model.dart';
import '../../utils/game_type_config.dart';
import '../../providers/auth_provider.dart';
import '../../providers/game_session_provider.dart';
import '../../services/game_question_catalog_service.dart';
import '../../services/game_session_service.dart';
import 'word_game_lobby_screen.dart';
import '../../localization/app_strings.dart';

String _questionCountLabel(String language) {
  const values = {'tr': 'Soru sayısı', 'en': 'Number of questions', 'de': 'Fragenanzahl', 'es': 'Número de preguntas', 'fr': 'Nombre de questions'};
  return values[language] ?? values['en']!;
}

String _questionCountOptionLabel(String language, int count) {
  const suffix = {'tr': 'soru', 'en': 'questions', 'de': 'Fragen', 'es': 'preguntas', 'fr': 'questions'};
  return '$count ${suffix[language] ?? suffix['en']}';
}

String _availableQuestionsMessage(String language, int available, int selected) {
  switch (language) {
    case 'tr': return 'Ortak görülmemiş $available soru bulundu. $selected soru seçilecek.';
    case 'de': return '$available ungesehene Fragen verfügbar. $selected werden ausgewählt.';
    case 'es': return 'Hay $available preguntas no vistas. Se elegirán $selected.';
    case 'fr': return '$available questions inédites disponibles. $selected seront sélectionnées.';
    default: return '$available unseen questions are available. $selected will be selected.';
  }
}

String _insufficientQuestionsMessage(String language, int available, int selected) {
  switch (language) {
    case 'tr': return 'Yalnızca $available ortak görülmemiş soru kaldı. En az $selected soru gerekli.';
    case 'de': return 'Nur noch $available ungesehene Fragen. Mindestens $selected sind erforderlich.';
    case 'es': return 'Solo quedan $available preguntas no vistas. Se necesitan al menos $selected.';
    case 'fr': return 'Il ne reste que $available questions inédites. Au moins $selected sont nécessaires.';
    default: return 'Only $available unseen questions remain. At least $selected are required.';
  }
}

class GameLobbyScreen extends StatefulWidget {
  final String gameType;

  const GameLobbyScreen({required this.gameType, Key? key}) : super(key: key);

  @override
  State<GameLobbyScreen> createState() => _GameLobbyScreenState();
}

class _GameLobbyScreenState extends State<GameLobbyScreen> {
  final Set<String> _selectedCategories = <String>{};
  int? _unseenCount;
  int _totalRounds = 15;
  bool _checkingAvailability = false;
  bool _started = false;
  bool _checkingActiveSession = true;
  GameSession? _activeSession;
  String? _availabilityError;

  String get gameType => widget.gameType;

  GameTypeConfig get config => GameTypeConfig.forType(gameType, locale: AppStrings.of(context).code);

  @override
  void initState() {
    super.initState();
    if (gameType != 'word_game') {
      _loadActiveSession();
    } else {
      _checkingActiveSession = false;
    }
  }

  Future<void> _loadActiveSession() async {
    final profile = context.read<AuthProvider>().profile;
    final partnerId = profile?.pairedWith;
    if (partnerId == null || partnerId.isEmpty) {
      if (mounted) setState(() => _checkingActiveSession = false);
      return;
    }

    try {
      final session = await GameSessionService(Supabase.instance.client)
          .getActiveSession(gameType: gameType, partnerId: partnerId);
      if (!mounted) return;
      setState(() {
        _activeSession = session;
        _checkingActiveSession = false;
        if (session != null) {
          _selectedCategories
            ..clear()
            ..addAll(session.categories);
          _started = true;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checkingActiveSession = false;
        _availabilityError = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (gameType == 'word_game') {
      return const WordGameLobbyScreen();
    }

    final profile = context.read<AuthProvider>().profile;
    final partnerId = profile?.pairedWith;

    if (_checkingActiveSession) {
      return Scaffold(
        appBar: AppBar(title: Text(config.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (partnerId == null || partnerId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(config.title)),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Bu oyunu oynamak için önce partnerinle eşleşmelisin.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (!_started) {
      return _CategorySelectionScreen(
        config: config,
        selectedCategories: _selectedCategories,
        unseenCount: _unseenCount,
        checkingAvailability: _checkingAvailability,
        availabilityError: _availabilityError,
        onCategoryToggle: _toggleCategory,
        totalRounds: _totalRounds,
        onTotalRoundsChanged: (value) async {
          setState(() { _totalRounds = value; _unseenCount = null; });
          await _refreshAvailability();
        },
        onContinue: _unseenCount != null && _unseenCount! >= _totalRounds
            ? () => setState(() => _started = true)
            : null,
      );
    }

    return ChangeNotifierProvider(
      create: (_) => GameSessionProvider(
        service: GameSessionService(Supabase.instance.client),
        gameType: gameType,
        partnerId: partnerId,
        totalRounds: _totalRounds,
        categories: _selectedCategories.toList(growable: false),
        initialSession: _activeSession,
      ),
      child: _GameLobbyBody(
        config: config,
        title: config.title,
        emoji: config.emoji,
        categories: _selectedCategories.toList(growable: false),
      ),
    );
  }

  Future<void> _toggleCategory(GameCategory category) async {
    if (_checkingAvailability) return;

    if (_selectedCategories.contains(category.id)) {
      setState(() {
        _selectedCategories.remove(category.id);
        _unseenCount = null;
        _availabilityError = null;
      });
    } else {
      if (_selectedCategories.length >= 5) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).t('max_categories'))),
        );
        return;
      }
      setState(() {
        _selectedCategories.add(category.id);
        _unseenCount = null;
        _availabilityError = null;
      });
    }

    await _refreshAvailability();
  }

  Future<void> _refreshAvailability() async {
    if (_selectedCategories.isEmpty) {
      if (!mounted) return;
      setState(() {
        _unseenCount = null;
        _availabilityError = null;
      });
      return;
    }

    setState(() {
      _checkingAvailability = true;
      _availabilityError = null;
    });

    try {
      final service = GameQuestionCatalogService(Supabase.instance.client);
      final count = await service.getUnseenQuestionCountForPair(
        gameType: gameType,
        categories: _selectedCategories.toList(growable: false),
      );
      if (!mounted) return;
      setState(() => _unseenCount = count);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _unseenCount = null;
        _availabilityError = error.toString();
      });
    } finally {
      if (mounted) setState(() => _checkingAvailability = false);
    }
  }
}

class _CategorySelectionScreen extends StatelessWidget {
  final GameTypeConfig config;
  final Set<String> selectedCategories;
  final int? unseenCount;
  final int totalRounds;
  final ValueChanged<int> onTotalRoundsChanged;
  final bool checkingAvailability;
  final String? availabilityError;
  final ValueChanged<GameCategory> onCategoryToggle;
  final VoidCallback? onContinue;

  const _CategorySelectionScreen({
    required this.config,
    required this.selectedCategories,
    required this.unseenCount,
    required this.totalRounds,
    required this.onTotalRoundsChanged,
    required this.checkingAvailability,
    required this.availabilityError,
    required this.onCategoryToggle,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final enoughQuestions = unseenCount != null && unseenCount! >= totalRounds;

    return Scaffold(
      appBar: AppBar(title: Text('${config.emoji} ${config.title}')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(AppStrings.of(context).t('customize_game'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(AppStrings.of(context).t('category_help')),
          const SizedBox(height: 18),
          DropdownButtonFormField<int>(
            value: totalRounds,
            decoration: InputDecoration(
              labelText: _questionCountLabel(config.locale),
              border: OutlineInputBorder(),
            ),
            items: const [5, 10, 15, 20, 25]
                .map((count) => DropdownMenuItem<int>(
              value: count,
              child: Text(_questionCountOptionLabel(config.locale, count)),
            ))
                .toList(),
            onChanged: (value) {
              if (value != null) onTotalRoundsChanged(value);
            },
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Chip(
                avatar: const Icon(Icons.category_outlined, size: 18),
                label: Text('${selectedCategories.length}/5 ${AppStrings.of(context).t('categories_count')}'),
              ),
              const SizedBox(width: 8),
              Chip(
                avatar: const Icon(Icons.quiz_outlined, size: 18),
                label: Text(_questionCountOptionLabel(config.locale, totalRounds)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...config.categories.map(
                (category) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: CheckboxListTile(
                value: selectedCategories.contains(category.id),
                onChanged: (_) => onCategoryToggle(category),
                title: Text('${category.emoji} ${category.title}'),
                subtitle: category.subcategories.isEmpty
                    ? null
                    : Text(category.subcategories.join(' • ')),
                secondary: selectedCategories.contains(category.id)
                    ? const Icon(Icons.check_circle)
                    : const Icon(Icons.add_circle_outline),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _AvailabilityStatus(
            checkingAvailability: checkingAvailability,
            availabilityError: availabilityError,
            unseenCount: unseenCount,
            enoughQuestions: enoughQuestions,
            config: config,
            totalRounds: totalRounds,
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: onContinue,
              icon: const Icon(Icons.arrow_forward),
              label: Text(AppStrings.of(context).t('create_game')),
            ),
          ),
        ],
      ),
    );
  }
}

class _GameLobbyBody extends StatelessWidget {
  final GameTypeConfig config;
  final String title;
  final String emoji;
  final List<String> categories;

  const _GameLobbyBody({
    required this.config,
    required this.title,
    required this.emoji,
    required this.categories,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<GameSessionProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          appBar: AppBar(title: Text('$emoji $title')),
          body: _buildBody(context, provider),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, GameSessionProvider provider) {
    if (provider.isLoading && provider.session == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.error != null && provider.session == null) {
      return _ErrorState(error: provider.error!, onRetry: provider.retry);
    }

    final session = provider.session;
    if (session == null) {
      return _ErrorState(
        error: 'Oyun oturumu oluşturulamadı.',
        onRetry: provider.retry,
      );
    }

    if (session.isPlaying) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        context.go('/home/game-round/${session.id}/${session.currentRound}');
      });
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () async => provider.retry(),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 56)),
                  const SizedBox(height: 12),
                  Text(
                    session.isPlaying ? 'Oyun başladı!' : 'Partnerin bekleniyor',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    session.isPlaying
                        ? 'İlk round hazır.'
                        : 'İkiniz aynı oyun oturumundasınız. Hazır olduğunda butona bas.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 20),
                  Chip(
                    avatar: const Icon(Icons.layers_outlined, size: 18),
                    label: Text('${session.totalRounds} ${AppStrings.of(context).t('questions')}'),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: categories.map((item) {
                      final category = config.categories.firstWhere(
                            (c) => c.id == item,
                        orElse: () => GameCategory(
                          id: item,
                          title: item,
                          emoji: '🎮',
                        ),
                      );
                      return Chip(
                        avatar: Text(category.emoji),
                        label: Text(category.title),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          if (provider.error != null) ...[
            const SizedBox(height: 12),
            _InlineError(message: provider.error!),
          ],
          const SizedBox(height: 20),
          Text(AppStrings.of(context).t('players'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...provider.players.map(
                (player) => _PlayerTile(
              player: player,
              isCurrentUser: player.userId == provider.currentUserId,
            ),
          ),
          if (provider.players.length < 2)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 20),
          if (session.isWaiting)
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: provider.currentPlayer == null ||
                    provider.isReadyLoading ||
                    provider.isStarting
                    ? null
                    : provider.toggleReady,
                icon: provider.isReadyLoading
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : Icon(
                  provider.currentPlayer?.ready == true
                      ? Icons.check_circle
                      : Icons.play_arrow,
                ),
                label: Text(
                  provider.currentPlayer?.ready == true ? 'Hazırım ✓' : 'Hazırım',
                ),
              ),
            ),
          const SizedBox(height: 14),
          if (session.isPlaying) ...[
            const _StartedInfo(),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: () {
                  context.push('/home/game-round/${session.id}/${session.currentRound}');
                },
                icon: const Icon(Icons.play_arrow),
                label: Text(AppStrings.of(context).t('first_round')),
              ),
            ),
          ] else if (provider.bothPlayersReady)
            const _ReadyInfo()
          else
            const Text(
              'Oyun, iki oyuncu da hazır olduğunda başlayacak.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => context.pop(),
            child: Text(AppStrings.of(context).t('exit_game')),
          ),
        ],
      ),
    );
  }
}

class _PlayerTile extends StatelessWidget {
  final GamePlayer player;
  final bool isCurrentUser;

  const _PlayerTile({required this.player, required this.isCurrentUser});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(player.ready ? Icons.check : Icons.person_outline),
        ),
        title: Text(isCurrentUser ? AppStrings.of(context).t('you') : AppStrings.of(context).t('partner')),
        subtitle: Text(player.ready ? AppStrings.of(context).t('ready') : AppStrings.of(context).t('not_ready')),
        trailing: player.ready
            ? const Icon(Icons.check_circle, color: Colors.green)
            : const Icon(Icons.hourglass_empty),
      ),
    );
  }
}

class _ReadyInfo extends StatelessWidget {
  const _ReadyInfo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.celebration_outlined, color: Colors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Text(AppStrings.of(context).t('both_ready_starting')),
          ),
        ],
      ),
    );
  }
}

class _StartedInfo extends StatelessWidget {
  const _StartedInfo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.play_circle_outline, color: Colors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Text(AppStrings.of(context).t('game_started')),
          ),
        ],
      ),
    );
  }
}

class _AvailabilityStatus extends StatelessWidget {
  final bool checkingAvailability;
  final String? availabilityError;
  final int? unseenCount;
  final bool enoughQuestions;
  final GameTypeConfig config;
  final int totalRounds;

  const _AvailabilityStatus({
    required this.checkingAvailability,
    required this.availabilityError,
    required this.unseenCount,
    required this.enoughQuestions,
    required this.config,
    required this.totalRounds,
  });

  @override
  Widget build(BuildContext context) {
    if (checkingAvailability) {
      return Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(AppStrings.of(context).t('seen_check')),
        ],
      );
    }

    if (availabilityError != null) {
      return _InlineError(message: availabilityError!);
    }

    if (unseenCount == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: enoughQuestions
            ? Colors.green.withOpacity(.10)
            : Colors.orange.withOpacity(.10),
      ),
      child: Row(
        children: [
          Icon(
            enoughQuestions
                ? Icons.check_circle_outline
                : Icons.info_outline,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              enoughQuestions
                  ? _availableQuestionsMessage(config.locale, unseenCount!, totalRounds)
                  : _insufficientQuestionsMessage(config.locale, unseenCount!, totalRounds),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;

  const _InlineError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 52),
            const SizedBox(height: 16),
            const Text(
              'Oyun oturumu oluşturulamadı',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(AppStrings.of(context).t('retry_game')),
            ),
          ],
        ),
      ),
    );
  }
}

