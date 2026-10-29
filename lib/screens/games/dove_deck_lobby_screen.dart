
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/dove_deck_session.dart';
import '../../models/dove_deck_rules.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../services/dove_deck_service.dart';
import 'dove_deck_game_screen.dart';

class DoveDeckLobbyScreen extends StatefulWidget {
  const DoveDeckLobbyScreen({super.key});

  @override
  State<DoveDeckLobbyScreen> createState() => _DoveDeckLobbyScreenState();
}

class _DoveDeckLobbyScreenState extends State<DoveDeckLobbyScreen> {
  late final DoveDeckService _service;

  DoveDeckSession? _game;
  StreamSubscription<DoveDeckSession>? _subscription;

  bool _loading = true;
  bool _actionBusy = false;
  bool _startingAutomatically = false;

  String? _openedGameId;
  String? _error;

  String _t(String key) {
    final lang = context.read<LocaleProvider>().locale.languageCode;

    const tr = <String, String>{
      'refresh': 'Devam eden oyunu yenile',
      'headline': 'Aynı maçta kalın. Hazır olduğunuzda birlikte başlayın.',
      'pair': 'Turtle Deck oynamak için önce partnerinle eşleşmelisin.',
      'new': 'Yeni oyun başlat',
      'playing': 'Devam eden maç',
      'waiting': 'Bekleyen maç',
      'room': 'Oda',
      'running': 'Oyun sürüyor. Bu oturuma devam et.',
      'waitingText': 'İkiniz de hazır olmadan maç başlamaz.',
      'yourStatus': 'Senin durumun',
      'ready': 'Hazırsın',
      'notReady': 'Henüz hazır değilsin',
      'partner': 'Partnerin',
      'wait': 'Bekleniyor',
      'notReadyButton': 'Hazır değilim',
      'readyButton': 'Hazırım',
      'partnerWait': 'Partnerin de hazır olduğunda oyun otomatik başlayacak.',
      'starting': 'İkiniz de hazırsınız. Oyun başlatılıyor…',
      'bothReady': 'İkiniz de hazırsınız. Oyun otomatik başlayacak.',
      'continue': 'Oyuna devam et',
      'unpaired': 'Önce partnerinle eşleşmelisin.',
      'loading': 'Oyun aranıyor…',
      'retry': 'Tekrar dene',
    };

    const en = <String, String>{
      'refresh': 'Refresh active game',
      'headline': 'Stay in the same match. Start together when you are ready.',
      'pair': 'Pair with your partner before playing Turtle Deck.',
      'new': 'Start a new game',
      'playing': 'Match in progress',
      'waiting': 'Waiting match',
      'room': 'Room',
      'running': 'The game is in progress. Continue this session.',
      'waitingText': 'The match starts when both players are ready.',
      'yourStatus': 'Your status',
      'ready': 'Ready',
      'notReady': 'Not ready yet',
      'partner': 'Partner',
      'wait': 'Waiting',
      'notReadyButton': 'Not ready',
      'readyButton': 'I’m ready',
      'partnerWait': 'The game starts automatically when your partner is ready.',
      'starting': 'You are both ready. Starting…',
      'bothReady': 'You are both ready. The game will start automatically.',
      'continue': 'Continue game',
      'unpaired': 'Pair with your partner first.',
      'loading': 'Looking for a game…',
      'retry': 'Try again',
    };

    const de = <String, String>{
      'refresh': 'Aktuelles Spiel laden',
      'headline': 'Bleibt im selben Spiel. Startet gemeinsam, wenn ihr bereit seid.',
      'pair': 'Kopple dich zuerst mit deinem Partner.',
      'new': 'Neues Spiel starten',
      'playing': 'Laufendes Spiel',
      'waiting': 'Wartendes Spiel',
      'room': 'Raum',
      'running': 'Das Spiel läuft. Setze diese Partie fort.',
      'waitingText': 'Beide Spieler müssen bereit sein.',
      'yourStatus': 'Dein Status',
      'ready': 'Bereit',
      'notReady': 'Noch nicht bereit',
      'partner': 'Partner',
      'wait': 'Wartet',
      'notReadyButton': 'Nicht bereit',
      'readyButton': 'Bereit',
      'partnerWait': 'Das Spiel startet automatisch, sobald dein Partner bereit ist.',
      'starting': 'Ihr seid beide bereit. Startet…',
      'bothReady': 'Ihr seid beide bereit. Das Spiel startet automatisch.',
      'continue': 'Spiel fortsetzen',
      'unpaired': 'Kopple dich zuerst mit deinem Partner.',
      'loading': 'Spiel wird gesucht…',
      'retry': 'Erneut versuchen',
    };

    const es = <String, String>{
      'refresh': 'Actualizar partida activa',
      'headline': 'Seguid en la misma partida. Empezad cuando ambos estéis listos.',
      'pair': 'Vincúlate con tu pareja antes de jugar.',
      'new': 'Iniciar partida',
      'playing': 'Partida en curso',
      'waiting': 'Partida en espera',
      'room': 'Sala',
      'running': 'La partida está en curso. Continúa esta sesión.',
      'waitingText': 'Ambos deben estar listos para empezar.',
      'yourStatus': 'Tu estado',
      'ready': 'Listo',
      'notReady': 'Aún no estás listo',
      'partner': 'Pareja',
      'wait': 'Esperando',
      'notReadyButton': 'No estoy listo',
      'readyButton': 'Estoy listo',
      'partnerWait': 'La partida empezará cuando tu pareja esté lista.',
      'starting': 'Ambos estáis listos. Iniciando…',
      'bothReady': 'Ambos estáis listos. La partida empezará automáticamente.',
      'continue': 'Continuar partida',
      'unpaired': 'Vincúlate con tu pareja primero.',
      'loading': 'Buscando partida…',
      'retry': 'Intentar de nuevo',
    };

    const fr = <String, String>{
      'refresh': 'Actualiser la partie',
      'headline': 'Restez dans la même partie. Lancez-la quand vous êtes prêts.',
      'pair': 'Associe-toi à ton partenaire avant de jouer.',
      'new': 'Nouvelle partie',
      'playing': 'Partie en cours',
      'waiting': 'Partie en attente',
      'room': 'Salon',
      'running': 'La partie est en cours. Reprends cette session.',
      'waitingText': 'Les deux joueurs doivent être prêts.',
      'yourStatus': 'Ton état',
      'ready': 'Prêt',
      'notReady': 'Pas encore prêt',
      'partner': 'Partenaire',
      'wait': 'En attente',
      'notReadyButton': 'Pas prêt',
      'readyButton': 'Je suis prêt',
      'partnerWait': 'La partie démarre automatiquement quand ton partenaire est prêt.',
      'starting': 'Vous êtes prêts tous les deux. Démarrage…',
      'bothReady': 'Vous êtes prêts tous les deux. La partie démarre automatiquement.',
      'continue': 'Continuer la partie',
      'unpaired': 'Associe-toi d’abord à ton partenaire.',
      'loading': 'Recherche de partie…',
      'retry': 'Réessayer',
    };

    final maps = <String, Map<String, String>>{
      'tr': tr,
      'en': en,
      'de': de,
      'es': es,
      'fr': fr,
    };

    final map = maps[lang] ?? en;
    return map[key] ?? en[key] ?? key;
  }

  @override
  void initState() {
    super.initState();

    _service = DoveDeckService(Supabase.instance.client);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreActiveGame();
    });
  }

  Future<void> _restoreActiveGame() async {
    final partnerId = context.read<AuthProvider>().profile?.pairedWith;

    if (partnerId == null || partnerId.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _t('unpaired');
          _game = null;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final game = await _service.findActiveGame(partnerId);

      if (!mounted) return;

      await _attachGame(game);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _createGame() async {
    final partnerId = context.read<AuthProvider>().profile?.pairedWith;

    if (partnerId == null || partnerId.isEmpty) {
      setState(() => _error = _t('unpaired'));
      return;
    }

    if (_actionBusy) return;

    setState(() {
      _actionBusy = true;
      _error = null;
    });

    try {
      final game = await _service.createOrGetPartnerGame(partnerId);

      if (!mounted) return;

      await _attachGame(game);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _actionBusy = false);
      }
    }
  }

  Future<void> _attachGame(DoveDeckSession? game) async {
    await _subscription?.cancel();
    _subscription = null;

    if (game == null) {
      if (mounted) {
        setState(() => _game = null);
      }
      return;
    }

    if (!mounted) return;

    setState(() => _game = game);

    _subscription = _service.watch(game.id).listen(
          (next) {
        if (!mounted) return;

        final current = _game;

        if (current != null && next.version < current.version) {
          return;
        }

        setState(() => _game = next);

        if (next.isPlaying) {
          _openGame(next);
        }

        _maybeAutoStart(next);
      },
      onError: (Object error) {
        // Realtime may temporarily disconnect on mobile networks.
        // The user can recover the latest state using the refresh action.
      },
    );

    if (game.isPlaying) {
      _openGame(game);
    } else {
      _maybeAutoStart(game);
    }
  }

  Future<void> _setReady(bool ready) async {
    final game = _game;

    if (game == null || _actionBusy) return;

    setState(() {
      _actionBusy = true;
      _error = null;
    });

    try {
      final updated = await _service.setReady(game.id, ready);

      if (mounted) {
        setState(() => _game = updated);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _actionBusy = false);

        final latest = _game;

        if (latest != null) {
          _maybeAutoStart(latest);
        }
      }
    }
  }

  void _openGame(DoveDeckSession game) {
    if (!mounted || _openedGameId == game.id) return;

    _openedGameId = game.id;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DoveDeckGameScreen(gameId: game.id),
        ),
      ).then((_) {
        if (!mounted) return;

        if (_openedGameId == game.id) {
          _openedGameId = null;
        }

        // Leaving the match should return to the games list, not re-attach
        // the still-active multiplayer session and immediately reopen it.
        context.go('/home');
      });
    });
  }

  void _maybeAutoStart(DoveDeckSession game) {
    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (!mounted ||
        _actionBusy ||
        _startingAutomatically ||
        !game.isWaiting ||
        !game.bothReady ||
        userId != game.playerOne) {
      return;
    }

    _startingAutomatically = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _startingAutomatically = false;
        return;
      }

      _startGame().whenComplete(() {
        _startingAutomatically = false;
      });
    });
  }

  Future<void> _startGame() async {
    final game = _game;

    if (game == null ||
        !game.isWaiting ||
        !game.bothReady ||
        _actionBusy) {
      return;
    }

    setState(() {
      _actionBusy = true;
      _error = null;
    });

    try {
      final rules = DoveDeckRules()..start();

      final started = await _service.start(
        game.id,
        rules.toJson(),
      );

      if (!mounted) return;

      setState(() => _game = started);

      _openGame(started);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _actionBusy = false);
      }
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final partnerId = profile?.pairedWith;

    final paired = partnerId != null && partnerId.isNotEmpty;
    final game = _game;

    final iAmReady =
        game != null && userId != null && game.isReady(userId);

    final isCreator = game != null && userId == game.playerOne;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F2EC),
      appBar: AppBar(
        title: const Text('Turtle Deck'),
        backgroundColor: const Color(0xFFF6F2EC),
        actions: [
          IconButton(
            tooltip: _t('refresh'),
            onPressed: _loading ? null : _restoreActiveGame,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF55466E),
                          Color(0xFF8274A0),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.style_rounded,
                          color: Colors.white,
                          size: 42,
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Turtle Deck',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _t('headline'),
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (_loading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ),
                    ),

                  if (!paired && !_loading)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(_t('pair')),
                      ),
                    ),

                  if (paired && !_loading && game == null)
                    FilledButton.icon(
                      onPressed: _actionBusy ? null : _createGame,
                      icon: const Icon(Icons.add_circle_outline),
                      label: Text(_t('new')),
                    ),

                  if (game != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              game.isPlaying
                                  ? _t('playing')
                                  : _t('waiting'),
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_t('room')}: '
                                  '${game.id.substring(0, game.id.length < 8 ? game.id.length : 8).toUpperCase()}',
                            ),
                            const SizedBox(height: 4),
                            Text(
                              game.isPlaying
                                  ? _t('running')
                                  : _t('waitingText'),
                            ),
                            const SizedBox(height: 12),

                            if (game.isWaiting) ...[
                              Text(
                                '${_t('yourStatus')}: '
                                    '${iAmReady ? _t('ready') : _t('notReady')}',
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_t('partner')}: '
                                    '${game.isReady(
                                  userId == game.playerOne
                                      ? game.playerTwo
                                      : game.playerOne,
                                ) ? _t('ready') : _t('wait')}',
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton(
                                onPressed: _actionBusy
                                    ? null
                                    : () => _setReady(!iAmReady),
                                child: Text(
                                  iAmReady
                                      ? _t('notReadyButton')
                                      : _t('readyButton'),
                                ),
                              ),
                              const SizedBox(height: 8),

                              if (isCreator && !game.bothReady)
                                Text(_t('partnerWait')),

                              if (isCreator && game.bothReady)
                                Text(_t('starting')),

                              if (!isCreator && game.bothReady)
                                Text(_t('bothReady')),
                            ],

                            if (game.isPlaying)
                              FilledButton.icon(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => DoveDeckGameScreen(
                                        gameId: game.id,
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: Text(_t('continue')),
                              ),
                          ],
                        ),
                      ),
                    ),

                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _error!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _loading ? null : _restoreActiveGame,
                            icon: const Icon(Icons.refresh),
                            label: Text(_t('retry')),
                          ),
                        ],
                      ),
                    ),

                  if (_actionBusy)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
