
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/dove_deck_rules.dart';
import '../../models/dove_deck_session.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../services/dove_deck_service.dart';

class DoveDeckGameScreen extends StatefulWidget {
  const DoveDeckGameScreen({super.key, required this.gameId});

  final String gameId;

  @override
  State<DoveDeckGameScreen> createState() => _DoveDeckGameScreenState();
}

class _DoveDeckGameScreenState extends State<DoveDeckGameScreen> {
  late final DoveDeckService _service;

  DoveDeckSession? _session;
  DoveDeckRules? _rules;

  bool _busy = false;
  bool _refreshing = false;
  String? _error;

  StreamSubscription<DoveDeckSession>? _subscription;
  Timer? _refreshTimer;

  String get _lang => context.read<LocaleProvider>().locale.languageCode;

  String _t(String key) {
    const tr = <String, String>{
      'rules': 'Oyun kuralları',
      'yourTurn': 'Sıra sende',
      'partnerTurn': 'Partnerinin sırası',
      'youWin': 'Kazandın! 🎉',
      'gameOver': 'Oyun bitti',
      'draw': 'Kart çek',
      'pass': 'Pas geç',
      'drawPile': 'ÇEKME DESTESİ',
      'discardPile': 'ATILAN KART',
      'partnerHand': 'PARTNERİNİN KARTLARI',
      'activeColor': 'Aktif renk',
      'chooseColor': 'Bir renk seç',
      'coral': 'Mercan',
      'ocean': 'Okyanus',
      'leaf': 'Yaprak',
      'sun': 'Güneş',
      'waiting': 'Partnerin hazır olduğunda oyun başlayacak.',
      'readyLobby': 'İkiniz de lobide Hazırım demelisiniz.',
      'backLobby': 'Lobiye dön',
      'yourPartnerTurn': 'Sıra partnerinde.',
      'stale': 'Diğer cihaz oyunu değiştirdi; güncel durum yüklendi.',
      'refresh': 'Oyunu yenile',
      'ruleIntro': 'Amaç, elindeki bütün kartları ilk bitiren oyuncu olmaktır.',
      'ruleMatch':
      'Sırası gelen oyuncu, atılan kartın rengiyle veya sayısıyla eşleşen bir kart oynar. Joker her zaman oynanabilir.',
      'ruleDraw':
      'Oynayacak kartın yoksa Kart çek düğmesini kullan. Çekme işleminden sonra gerekiyorsa Pas geç ile sıranı bitir.',
      'ruleSpecial':
      'ATLA ve TERS iki kişilik oyunda rakibin sırasını atlatır. +2 ve +4 kartları ceza kartı çektirir.',
      'ruleWild': 'Joker oynadığında aktif rengi seç.',
      'ruleWin':
      'Elindeki son kartı oynadığında kazanırsın. Hamleler iki cihaz arasında eşitlenir.',
      'loading': 'Oyun yükleniyor…',
      'status': 'Oyun durumu',
      'connection': 'Canlı bağlantı kesildi. Yeniden deneyin.',
      'drawPenalty': 'Ceza kartlarını çek',
      'pendingDraw': 'Bekleyen ceza',
    };

    const en = <String, String>{
      'rules': 'Game rules',
      'yourTurn': 'YOUR TURN',
      'partnerTurn': "PARTNER'S TURN",
      'youWin': 'You win! 🎉',
      'gameOver': 'Game over',
      'draw': 'Draw card',
      'pass': 'Pass',
      'drawPile': 'DRAW PILE',
      'discardPile': 'DISCARD PILE',
      'partnerHand': "PARTNER'S HAND",
      'activeColor': 'Active colour',
      'chooseColor': 'Choose a colour',
      'coral': 'Coral',
      'ocean': 'Ocean',
      'leaf': 'Leaf',
      'sun': 'Sun',
      'waiting': 'The game starts when your partner is ready.',
      'readyLobby': 'Both players must tap Ready in the lobby.',
      'backLobby': 'Back to lobby',
      'yourPartnerTurn': "It's your partner's turn.",
      'stale': 'The other device changed the game. Latest state loaded.',
      'refresh': 'Refresh game',
      'ruleIntro': 'Be the first player to get rid of every card in your hand.',
      'ruleMatch':
      'Play a card matching the top discard by colour or number. Wild cards can be played at any time.',
      'ruleDraw':
      'If you cannot play, draw a card. Pass when required to finish your turn.',
      'ruleSpecial':
      'Skip and Reverse skip your opponent in this two-player game. Draw cards apply penalties.',
      'ruleWild': 'Choose the active colour after playing a Wild.',
      'ruleWin': 'Play your last card to win. Moves sync between both devices.',
      'loading': 'Loading game…',
      'status': 'Game status',
      'connection': 'Live connection lost. Please try again.',
      'drawPenalty': 'Draw penalty cards',
      'pendingDraw': 'Pending penalty',
    };

    const de = <String, String>{
      'rules': 'Spielregeln',
      'yourTurn': 'DU BIST DRAN',
      'partnerTurn': 'PARTNER IST DRAN',
      'youWin': 'Du gewinnst! 🎉',
      'gameOver': 'Spiel beendet',
      'draw': 'Karte ziehen',
      'pass': 'Passen',
      'drawPile': 'NACHZIEHSTAPEL',
      'discardPile': 'ABLAGESTAPEL',
      'partnerHand': 'KARTEN DES PARTNERS',
      'activeColor': 'Aktive Farbe',
      'chooseColor': 'Farbe wählen',
      'coral': 'Koralle',
      'ocean': 'Ozean',
      'leaf': 'Blatt',
      'sun': 'Sonne',
      'waiting': 'Das Spiel beginnt, sobald dein Partner bereit ist.',
      'readyLobby': 'Beide Spieler müssen in der Lobby auf Bereit tippen.',
      'backLobby': 'Zur Lobby',
      'yourPartnerTurn': 'Dein Partner ist dran.',
      'stale': 'Das andere Gerät hat das Spiel geändert. Aktueller Stand geladen.',
      'refresh': 'Spiel aktualisieren',
      'ruleIntro': 'Gewinne, indem du als Erster alle Karten auf deiner Hand ablegst.',
      'ruleMatch': 'Spiele eine Karte mit passender Farbe oder Zahl. Joker können jederzeit gespielt werden.',
      'ruleDraw': 'Wenn du nicht spielen kannst, ziehe eine Karte. Passe, wenn nötig.',
      'ruleSpecial': 'Aussetzen und Richtungswechsel überspringen im Zweierspiel den Gegner. Ziehkarten verursachen Strafkarten.',
      'ruleWild': 'Wähle nach einem Joker die aktive Farbe.',
      'ruleWin': 'Lege deine letzte Karte ab, um zu gewinnen. Züge werden synchronisiert.',
      'loading': 'Spiel wird geladen…',
      'status': 'Spielstatus',
      'connection': 'Live-Verbindung unterbrochen. Bitte erneut versuchen.',
      'drawPenalty': 'Strafkarten ziehen',
      'pendingDraw': 'Ausstehende Strafe',
    };

    const es = <String, String>{
      'rules': 'Reglas del juego',
      'yourTurn': 'TU TURNO',
      'partnerTurn': 'TURNO DE TU PAREJA',
      'youWin': '¡Has ganado! 🎉',
      'gameOver': 'Fin del juego',
      'draw': 'Robar carta',
      'pass': 'Pasar',
      'drawPile': 'MAZO',
      'discardPile': 'DESCARTES',
      'partnerHand': 'CARTAS DE TU PAREJA',
      'activeColor': 'Color activo',
      'chooseColor': 'Elige un color',
      'coral': 'Coral',
      'ocean': 'Océano',
      'leaf': 'Hoja',
      'sun': 'Sol',
      'waiting': 'La partida empieza cuando tu pareja esté lista.',
      'readyLobby': 'Ambos deben pulsar Listo en la sala.',
      'backLobby': 'Volver a la sala',
      'yourPartnerTurn': 'Es el turno de tu pareja.',
      'stale': 'El otro dispositivo cambió la partida. Estado actualizado cargado.',
      'refresh': 'Actualizar partida',
      'ruleIntro': 'Gana quien se quede sin cartas primero.',
      'ruleMatch': 'Juega una carta del mismo color o número. Los comodines se pueden jugar en cualquier momento.',
      'ruleDraw': 'Si no puedes jugar, roba una carta. Pasa cuando sea necesario.',
      'ruleSpecial': 'Salto y Reversa saltan al rival en partidas de dos. Las cartas de robo aplican penalizaciones.',
      'ruleWild': 'Al jugar un comodín, elige el color activo.',
      'ruleWin': 'Juega tu última carta para ganar. Los movimientos se sincronizan.',
      'loading': 'Cargando partida…',
      'status': 'Estado de la partida',
      'connection': 'Se perdió la conexión en vivo. Inténtalo de nuevo.',
      'drawPenalty': 'Robar cartas de penalización',
      'pendingDraw': 'Penalización pendiente',
    };

    const fr = <String, String>{
      'rules': 'Règles du jeu',
      'yourTurn': 'À TOI DE JOUER',
      'partnerTurn': 'AU TOUR DU PARTENAIRE',
      'youWin': 'Tu as gagné ! 🎉',
      'gameOver': 'Partie terminée',
      'draw': 'Piocher',
      'pass': 'Passer',
      'drawPile': 'PIOCHE',
      'discardPile': 'DÉFAUSSE',
      'partnerHand': 'CARTES DU PARTENAIRE',
      'activeColor': 'Couleur active',
      'chooseColor': 'Choisir une couleur',
      'coral': 'Corail',
      'ocean': 'Océan',
      'leaf': 'Feuille',
      'sun': 'Soleil',
      'waiting': 'La partie commence quand ton partenaire est prêt.',
      'readyLobby': 'Les deux joueurs doivent appuyer sur Prêt dans le salon.',
      'backLobby': 'Retour au salon',
      'yourPartnerTurn': "C'est au tour de ton partenaire.",
      'stale': "L'autre appareil a modifié la partie. L'état actuel a été chargé.",
      'refresh': 'Actualiser la partie',
      'ruleIntro': 'Le premier joueur qui se débarrasse de toutes ses cartes gagne.',
      'ruleMatch': 'Joue une carte de la même couleur ou du même numéro. Les jokers peuvent être joués à tout moment.',
      'ruleDraw': 'Si tu ne peux pas jouer, pioche une carte. Passe si nécessaire.',
      'ruleSpecial': 'Passer et Inversion sautent le tour adverse à deux joueurs. Les cartes de pioche appliquent des pénalités.',
      'ruleWild': 'Après un joker, choisis la couleur active.',
      'ruleWin': 'Joue ta dernière carte pour gagner. Les coups sont synchronisés.',
      'loading': 'Chargement…',
      'status': 'État de la partie',
      'connection': 'Connexion en direct perdue. Réessaie.',
      'drawPenalty': 'Piocher les cartes de pénalité',
      'pendingDraw': 'Pénalité en attente',
    };

    final maps = <String, Map<String, String>>{
      'tr': tr,
      'en': en,
      'de': de,
      'es': es,
      'fr': fr,
    };

    final map = maps[_lang] ?? en;
    return map[key] ?? en[key] ?? key;
  }

  @override
  void initState() {
    super.initState();

    _service = DoveDeckService(Supabase.instance.client);

    _load();

    _subscription = _service.watch(widget.gameId).listen(
          (next) {
        if (!mounted) return;

        if (_busy && next.version < (_session?.version ?? 0)) {
          return;
        }

        if (_session != null && next.version < _session!.version) {
          return;
        }

        setState(() {
          _session = next;
          _rules = next.isPlaying && next.state.isNotEmpty
              ? _decode(next.state)
              : null;
          _error = null;
        });
      },
      onError: (_) {
        if (mounted) {
          setState(() => _error = _t('connection'));
        }
      },
    );

    _refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
          (_) => unawaited(_load(silent: true)),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (_refreshing) return;

    _refreshing = true;

    try {
      final row = await Supabase.instance.client
          .from('dove_deck_games')
          .select()
          .eq('id', widget.gameId)
          .single();

      final session = DoveDeckSession.fromMap(row);

      if (!mounted) return;

      if (_session != null && session.version < _session!.version) {
        return;
      }

      if (!_busy) {
        setState(() {
          _session = session;
          _rules = session.isPlaying && session.state.isNotEmpty
              ? _decode(session.state)
              : null;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() => _error = e.toString());
      }
    } finally {
      _refreshing = false;
    }
  }

  DoveDeckRules _decode(Map<String, dynamic> json) {
    return DoveDeckRules.fromJson(json);
  }

  Map<String, dynamic> _encode(DoveDeckRules rules) {
    return rules.toJson();
  }

  Future<void> _saveMove(
      void Function(DoveDeckRules rules) move,
      ) async {
    final session = _session;
    final current = _rules;

    if (session == null || current == null || _busy) return;

    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (session.currentTurn != userId) {
      setState(() => _error = _t('yourPartnerTurn'));
      return;
    }

    final before = _encode(current);

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      move(current);

      final nextUser = current.finished
          ? session.currentTurn
          : session.currentTurn == session.playerOne
          ? session.playerTwo
          : session.playerOne;

      final next = await _service.submitState(
        gameId: session.id,
        expectedVersion: session.version,
        state: _encode(current),
        nextTurn: nextUser,
        winner: current.finished
            ? (current.winner == 0
            ? session.playerOne
            : session.playerTwo)
            : null,
      );

      if (!mounted) return;

      setState(() {
        _session = next;
        _rules = next.isPlaying && next.state.isNotEmpty
            ? _decode(next.state)
            : current;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _rules = _decode(before);
        _error = e.toString().contains('STALE_GAME_STATE')
            ? _t('stale')
            : e.toString();
      });

      await _load();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Color _suitColor(DoveSuit? suit) => switch (suit) {
    DoveSuit.coral => const Color(0xFFE66D75),
    DoveSuit.ocean => const Color(0xFF3678C8),
    DoveSuit.leaf => const Color(0xFF39966B),
    DoveSuit.sun => const Color(0xFFE0A52F),
    null => const Color(0xFF55466E),
  };

  String _suitName(DoveSuit suit) {
    return _t(switch (suit) {
      DoveSuit.coral => 'coral',
      DoveSuit.ocean => 'ocean',
      DoveSuit.leaf => 'leaf',
      DoveSuit.sun => 'sun',
    });
  }

  Future<DoveSuit?> _chooseSuit() {
    return showDialog<DoveSuit>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('chooseColor')),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: DoveSuit.values.map((suit) {
            return InkWell(
              onTap: () => Navigator.pop(ctx, suit),
              child: CircleAvatar(
                backgroundColor: _suitColor(suit),
                child: Text(
                  _suitName(suit),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  String _cardLabel(DoveCard card) => switch (card.kind) {
    DoveCardKind.number => '${card.number ?? 0}',
    DoveCardKind.skip => switch (_lang) {
      'tr' => 'ATLA',
      'de' => 'AUS',
      'es' => 'SALTA',
      'fr' => 'SAUT',
      _ => 'SKIP',
    },
    DoveCardKind.reverse => switch (_lang) {
      'tr' => 'TERS',
      'de' => 'WECH',
      'es' => 'REV',
      'fr' => 'INV',
      _ => 'REV',
    },
    DoveCardKind.drawTwo => '+2',
    DoveCardKind.wild => _lang == 'es' ? 'COMODÍN' : 'WILD',
    DoveCardKind.wildDrawFour => '+4',
  };

  Future<void> _showRules() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * .82,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF173B34),
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(30),
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0x66FFF4DD),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Icon(
                      Icons.menu_book_rounded,
                      color: Color(0xFFE4BD76),
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _t('rules'),
                        style: const TextStyle(
                          color: Color(0xFFFFF4DD),
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _ruleLine('01', _t('ruleIntro')),
                _ruleLine('02', _t('ruleMatch')),
                _ruleLine('03', _t('ruleDraw')),
                _ruleLine('04', _t('ruleSpecial')),
                _ruleLine('05', _t('ruleWild')),
                _ruleLine('06', _t('ruleWin')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ruleLine(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0x26E4BD76),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0x80E4BD76),
              ),
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: Color(0xFFE4BD76),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                text,
                style: const TextStyle(
                  color: Color(0xFFFFF4DD),
                  height: 1.4,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final rules = _rules;

    final userId = context.watch<AuthProvider>().profile?.id ??
        Supabase.instance.client.auth.currentUser?.id;

    if (session == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('DOVE DECK'),
          actions: [
            IconButton(
              tooltip: _t('refresh'),
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Center(
          child: _error == null
              ? Text(_t('loading'))
              : Text(_error!),
        ),
      );
    }

    final myIndex = userId == session.playerOne ? 0 : 1;
    final myTurn = session.currentTurn == userId;

    final safeTopCard =
    rules != null && rules.discardPile.isNotEmpty
        ? rules.topCard
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFF102B28),
      appBar: AppBar(
        title: const Text('DOVE DECK'),
        backgroundColor: const Color(0xFF102B28),
        foregroundColor: const Color(0xFFF7F1E4),
        actions: [
          IconButton(
            tooltip: _t('rules'),
            onPressed: _showRules,
            icon: const Icon(
              Icons.menu_book_rounded,
              color: Color(0xFFE4BD76),
            ),
          ),
          IconButton(
            tooltip: _t('refresh'),
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: rules == null || safeTopCard == null
            ? Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.style,
                  size: 64,
                  color: Color(0xFF55466E),
                ),
                const SizedBox(height: 12),
                Text(
                  session.isWaiting
                      ? _t('waiting')
                      : '${_t('status')}: ${session.status.toUpperCase()}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                if (session.isWaiting)
                  Text(
                    _t('readyLobby'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                if (session.isWaiting)
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(_t('backLobby')),
                  ),
                if (_error != null)
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
              ],
            ),
          ),
        )
            : Column(
          children: [
            const SizedBox(height: 10),
            Text(
              session.isFinished
                  ? (session.winner == userId
                  ? _t('youWin')
                  : _t('gameOver'))
                  : myTurn
                  ? _t('yourTurn')
                  : _t('partnerTurn'),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
                color: Color(0xFFF7F1E4),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _pile(
                  _t('drawPile'),
                  rules.drawPile.length,
                  const Color(0xFF55466E),
                ),
                const SizedBox(width: 18),
                _pile(
                  _t('discardPile'),
                  rules.discardPile.length,
                  _suitColor(safeTopCard.suit),
                  label: _cardLabel(safeTopCard),
                ),
              ],
            ),
            if (rules.chosenSuit != null)
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  '${_t('activeColor')}: ${_suitName(rules.chosenSuit!)}',
                  style: const TextStyle(color: Color(0xFFF7F1E4)),
                ),
              ),
            if (rules.pendingDraw > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${_t('pendingDraw')}: ${rules.pendingDraw}',
                  style: const TextStyle(
                    color: Color(0xFFE4BD76),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              '${_t('partnerHand')}  ·  ${rules.hands[1 - myIndex].length}',
              style: const TextStyle(color: Color(0xFFE8E1D4)),
            ),
            const Divider(color: Color(0x33FFFFFF)),
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  height: 220,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: rules.hands[myIndex]
                          .asMap()
                          .entries
                          .map((entry) {
                        final card = entry.value;
                        final index = entry.key;

                        final enabled = myTurn &&
                            !_busy &&
                            !session.isFinished &&
                            rules.currentPlayer == myIndex &&
                            rules.canPlay(card);

                        return InkWell(
                          onTap: enabled
                              ? () async {
                            DoveSuit? suit;

                            if (card.isWild) {
                              suit = await _chooseSuit();
                              if (suit == null || !mounted) {
                                return;
                              }
                            }

                            await _saveMove(
                                  (r) => r.play(
                                card.id,
                                wildSuit: suit,
                              ),
                            );
                          }
                              : null,
                          child: Transform.translate(
                            offset: Offset(
                              0,
                              index.isEven ? 8 : 0,
                            ),
                            child: Transform.rotate(
                              angle: (index -
                                  (rules.hands[myIndex].length - 1) /
                                      2) *
                                  0.035,
                              child: Container(
                                width: 82,
                                height: 142,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      _suitColor(card.suit)
                                          .withValues(alpha: .96),
                                      _suitColor(card.suit),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: const Color(0xFFFFF4DC),
                                    width: 2.5,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black38,
                                      blurRadius: 12,
                                      offset: Offset(0, 7),
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Transform.rotate(
                                      angle: -.35,
                                      child: Container(
                                        width: 56,
                                        height: 100,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: .16,
                                          ),
                                          borderRadius:
                                          BorderRadius.circular(40),
                                          border: Border.all(
                                            color: Colors.white
                                                .withValues(alpha: .75),
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _cardLabel(card),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 25,
                                        fontWeight: FontWeight.w900,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black26,
                                            blurRadius: 4,
                                            offset: Offset(1, 2),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Positioned(
                                      top: 8,
                                      left: 10,
                                      child: Text(
                                        _cardLabel(card),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 8,
                                      right: 10,
                                      child: Icon(
                                        Icons.favorite_rounded,
                                        size: 13,
                                        color: Colors.white.withValues(
                                          alpha: .85,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: myTurn &&
                          !_busy &&
                          !rules.mustPassAfterDraw &&
                          !session.isFinished
                          ? () => _saveMove((r) => r.draw())
                          : null,
                      icon: const Icon(Icons.add),
                      label: Text(
                        rules.pendingDraw > 0
                            ? _t('drawPenalty')
                            : _t('draw'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: myTurn &&
                          !_busy &&
                          rules.mustPassAfterDraw &&
                          !session.isFinished
                          ? () => _saveMove((r) => r.pass())
                          : null,
                      icon: const Icon(Icons.skip_next),
                      label: Text(_t('pass')),
                    ),
                  ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _pile(
      String title,
      int count,
      Color color, {
        String? label,
      }) {
    return Column(
      children: [
        Container(
          width: 94,
          height: 132,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withValues(alpha: .72)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFFFFF4DC),
              width: 2.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 14,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: 70,
              height: 106,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(38),
                border: Border.all(
                  color: Colors.white.withValues(alpha: .7),
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  label ?? '♡\n$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 23,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '$title ($count)',
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFFE8E1D4),
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }
}
