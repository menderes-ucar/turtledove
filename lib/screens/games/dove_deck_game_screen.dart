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
  String? _error;
  StreamSubscription<DoveDeckSession>? _subscription;

  Timer? _refreshTimer;
  bool _refreshing = false;

  String get _lang => context.read<LocaleProvider>().locale.languageCode;
  String _t(String key) {
    const tr = <String, String>{
      'rules':'Oyun kuralları','yourTurn':'Sıra sende','partnerTurn':'Partnerinin sırası','youWin':'Kazandın! 🎉','gameOver':'Oyun bitti',
      'draw':'Kart çek','pass':'Pas geç','drawPile':'Çekme destesi','discardPile':'Atılan kart','partnerHand':'PARTNERİNİN KARTLARI',
      'activeColor':'Aktif renk','chooseColor':'Bir renk seç','coral':'Mercan','ocean':'Okyanus','leaf':'Yaprak','sun':'Güneş',
      'waiting':'Partnerin hazır olduğunda oyun başlayacak.','readyLobby':'İkiniz de lobide Hazırım demelisiniz.','backLobby':'Lobiye dön',
      'yourPartnerTurn':'Sıra partnerinde.','stale':'Diğer cihaz oyunu değiştirdi; güncel durum yüklendi.','refresh':'Oyunu yenile',
      'ruleIntro':'Amaç, elindeki bütün kartları ilk bitiren oyuncu olmaktır.',
      'ruleMatch':'Sırası gelen oyuncu, atılan kartın rengiyle veya sayısıyla eşleşen bir kart oynar. Joker her zaman oynanabilir.',
      'ruleDraw':'Oynayacak kartın yoksa Kart çek’e bas. Çektiğin karttan sonra Pas geç ile sıranı bitir.',
      'ruleSpecial':'ATLA ve TERS iki kişilik oyunda rakibin sırasını atlatır. +2 rakibe iki, +4 dört kart çektirir.',
      'ruleWild':'Joker oynadığında aktif rengi seç. +4 oynandığında rakip dört kart çeker.',
      'ruleWin':'Elindeki son kartı oynadığında kazanırsın. Hamleler iki cihaz arasında otomatik eşitlenir.',
      'loading':'Oyun yükleniyor…','status':'Oyun durumu','connection':'Canlı bağlantı kesildi. Yeniden deneyin.'
    };
    const en = <String, String>{
      'rules':'Game rules','yourTurn':'YOUR TURN','partnerTurn':\"PARTNER'S TURN\",'youWin':'You win! 🎉','gameOver':'Game over',
      'draw':'Draw card','pass':'Pass','drawPile':'DRAW PILE','discardPile':'DISCARD PILE','partnerHand':"PARTNER'S HAND",
      'activeColor':'Active colour','chooseColor':'Choose a colour','coral':'Coral','ocean':'Ocean','leaf':'Leaf','sun':'Sun',
      'waiting':'The game starts when your partner is ready.','readyLobby':'Both players must tap Ready in the lobby.','backLobby':'Back to lobby',
      'yourPartnerTurn':"It's your partner's turn.",'stale':'The other device changed the game. Latest state loaded.','refresh':'Refresh game',
      'ruleIntro':'Be the first player to get rid of every card in your hand.',
      'ruleMatch':'Play a card matching the top discard by colour or number. Wild cards can be played at any time.',
      'ruleDraw':'If you cannot play, tap Draw card. After drawing, tap Pass to end your turn.',
      'ruleSpecial':'SKIP and REVERSE skip your opponent in this two-player game. +2 makes them draw two cards; +4 makes them draw four.',
      'ruleWild':'When playing a Wild, choose the active colour. A Wild +4 makes your opponent draw four cards.',
      'ruleWin':'Play your last card to win. Moves sync automatically between both devices.',
      'loading':'Loading game…','status':'Game status','connection':'Live connection lost. Please try again.'
    };
    const de = <String, String>{
      'rules':'Spielregeln','yourTurn':'DU BIST DRAN','partnerTurn':'PARTNER IST DRAN','youWin':'Du gewinnst! 🎉','gameOver':'Spiel beendet',
      'draw':'Karte ziehen','pass':'Passen','drawPile':'NACHZIEHSTAPEL','discardPile':'ABLAGESTAPEL','partnerHand':'KARTEN DES PARTNERS',
      'activeColor':'Aktive Farbe','chooseColor':'Farbe wählen','coral':'Koralle','ocean':'Ozean','leaf':'Blatt','sun':'Sonne',
      'waiting':'Das Spiel beginnt, sobald dein Partner bereit ist.','readyLobby':'Beide Spieler müssen in der Lobby auf Bereit tippen.','backLobby':'Zur Lobby',
      'yourPartnerTurn':'Dein Partner ist dran.','stale':'Das andere Gerät hat das Spiel geändert. Aktueller Stand geladen.','refresh':'Spiel aktualisieren',
      'ruleIntro':'Gewinne, indem du als Erster alle Karten auf deiner Hand ablegst.',
      'ruleMatch':'Spiele eine Karte mit passender Farbe oder Zahl. Joker können jederzeit gespielt werden.',
      'ruleDraw':'Wenn du nicht spielen kannst, ziehe eine Karte. Tippe danach auf Passen.',
      'ruleSpecial':'Aussetzen und Richtungswechsel überspringen im Zweierspiel den Gegner. +2 zieht zwei, +4 vier Karten.',
      'ruleWild':'Wähle nach einem Joker die aktive Farbe. Joker +4 lässt den Gegner vier Karten ziehen.',
      'ruleWin':'Lege deine letzte Karte ab, um zu gewinnen. Züge werden automatisch auf beiden Geräten synchronisiert.',
      'loading':'Spiel wird geladen…','status':'Spielstatus','connection':'Live-Verbindung unterbrochen. Bitte erneut versuchen.'
    };
    const es = <String, String>{
      'rules':'Reglas del juego','yourTurn':'TU TURNO','partnerTurn':'TURNO DE TU PAREJA','youWin':'¡Has ganado! 🎉','gameOver':'Fin del juego',
      'draw':'Robar carta','pass':'Pasar','drawPile':'MAZO','discardPile':'DESCARTES','partnerHand':'CARTAS DE TU PAREJA',
      'activeColor':'Color activo','chooseColor':'Elige un color','coral':'Coral','ocean':'Océano','leaf':'Hoja','sun':'Sol',
      'waiting':'La partida empieza cuando tu pareja esté lista.','readyLobby':'Ambos deben pulsar Listo en la sala.','backLobby':'Volver a la sala',
      'yourPartnerTurn':'Es el turno de tu pareja.','stale':'El otro dispositivo cambió la partida. Se cargó el estado actualizado.','refresh':'Actualizar partida',
      'ruleIntro':'Gana quien se quede sin cartas primero.',
      'ruleMatch':'Juega una carta del mismo color o número que la carta superior. Los comodines se pueden jugar en cualquier momento.',
      'ruleDraw':'Si no puedes jugar, roba una carta. Después pulsa Pasar para terminar tu turno.',
      'ruleSpecial':'Salto y Reversa saltan al rival en partidas de dos. +2 hace robar dos cartas y +4 cuatro.',
      'ruleWild':'Al jugar un comodín, elige el color activo. El comodín +4 hace que el rival robe cuatro cartas.',
      'ruleWin':'Juega tu última carta para ganar. Los movimientos se sincronizan entre ambos dispositivos.',
      'loading':'Cargando partida…','status':'Estado de la partida','connection':'Se perdió la conexión en vivo. Inténtalo de nuevo.'
    };
    const fr = <String, String>{
      'rules':'Règles du jeu','yourTurn':'À TOI DE JOUER','partnerTurn':'AU TOUR DU PARTENAIRE','youWin':'Tu as gagné ! 🎉','gameOver':'Partie terminée',
      'draw':'Piocher','pass':'Passer','drawPile':'PIOCHE','discardPile':'DÉFAUSSE','partnerHand':'CARTES DU PARTENAIRE',
      'activeColor':'Couleur active','chooseColor':'Choisir une couleur','coral':'Corail','ocean':'Océan','leaf':'Feuille','sun':'Soleil',
      'waiting':'La partie commence quand ton partenaire est prêt.','readyLobby':'Les deux joueurs doivent appuyer sur Prêt dans le salon.','backLobby':'Retour au salon',
      'yourPartnerTurn':"C'est au tour de ton partenaire.",'stale':"L'autre appareil a modifié la partie. L'état actuel a été chargé.",'refresh':'Actualiser la partie',
      'ruleIntro':'Le premier joueur qui se débarrasse de toutes ses cartes gagne.',
      'ruleMatch':'Joue une carte de la même couleur ou du même numéro que la défausse. Les jokers peuvent être joués à tout moment.',
      'ruleDraw':'Si tu ne peux pas jouer, pioche une carte. Appuie ensuite sur Passer pour terminer ton tour.',
      'ruleSpecial':'Passer et Inversion sautent le tour adverse à deux joueurs. +2 fait piocher deux cartes, +4 en fait piocher quatre.',
      'ruleWild':'Après un joker, choisis la couleur active. Le joker +4 oblige le partenaire à piocher quatre cartes.',
      'ruleWin':'Joue ta dernière carte pour gagner. Les coups sont synchronisés automatiquement sur les deux appareils.',
      'loading':'Chargement…','status':'État de la partie','connection':'Connexion en direct perdue. Réessaie.'
    };
    final map = <String, Map<String, String>>{'tr':tr,'en':en,'de':de,'es':es,'fr':fr}[_lang] ?? en;
    return map[key] ?? en[key] ?? key;
  }


  @override
  void initState() {
    super.initState();
    _service = DoveDeckService(Supabase.instance.client);
    _load();
    _subscription = _service.watch(widget.gameId).listen((next) {
      if (!mounted || (_busy && next.version < (_session?.version ?? 0))) return;
      if (_session != null && next.version < _session!.version) return;
      setState(() {
        _session = next;
        _rules = next.isPlaying && next.state.isNotEmpty ? _decode(next.state) : null;
        _error = null;
      });
    }, onError: (_) {
      if (mounted) setState(() => _error = _t('connection'));
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) => unawaited(_load(silent: true)));
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
      final row = await Supabase.instance.client.from('dove_deck_games').select().eq('id', widget.gameId).single();
      final session = DoveDeckSession.fromMap(row);
      if (!mounted) return;
      if (_session != null && session.version < _session!.version) return;
      if (mounted && !_busy) setState(() {
        _session = session;
        _rules = session.isPlaying && session.state.isNotEmpty ? _decode(session.state) : null;
        _error = null;
      });
    } catch (e) {
      if (mounted && !silent) setState(() => _error = e.toString());
    } finally {
      _refreshing = false;
    }
  }

  DoveDeckRules _decode(Map<String, dynamic> json) {
    final r = DoveDeckRules();
    List<DoveCard> cards(dynamic value) => (value as List? ?? const [])
        .map((e) => DoveCard.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    r.hands = [
      cards(json['hands'] is List && (json['hands'] as List).isNotEmpty ? json['hands'][0] : []),
      cards(json['hands'] is List && (json['hands'] as List).length > 1 ? json['hands'][1] : []),
    ];
    r.drawPile = cards(json['drawPile']);
    r.discardPile = cards(json['discardPile']);
    r.currentPlayer = (json['currentPlayer'] as num?)?.toInt() ?? 0;
    r.chosenSuit = json['chosenSuit'] == null ? null : DoveSuit.values.byName(json['chosenSuit'] as String);
    r.finished = json['finished'] == true;
    r.winner = (json['winner'] as num?)?.toInt();
    r.mustPassAfterDraw = json['mustPassAfterDraw'] == true;
    return r;
  }

  Map<String, dynamic> _encode(DoveDeckRules r) => {
    'hands': r.hands.map((h) => h.map((c) => c.toJson()).toList()).toList(),
    'drawPile': r.drawPile.map((c) => c.toJson()).toList(),
    'discardPile': r.discardPile.map((c) => c.toJson()).toList(),
    'currentPlayer': r.currentPlayer,
    'chosenSuit': r.chosenSuit?.name,
    'finished': r.finished,
    'winner': r.winner,
    'mustPassAfterDraw': r.mustPassAfterDraw,
  };

  Future<void> _start() async {
    final session = _session;
    if (session == null || _busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final rules = DoveDeckRules()..start();
      final next = await _service.start(session.id, _encode(rules));
      if (!mounted) return;
      setState(() { _rules = rules; _session = next; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveMove(void Function(DoveDeckRules) move) async {
    final session = _session;
    final current = _rules;
    if (session == null || current == null || _busy) return;
    if (session.currentTurn != Supabase.instance.client.auth.currentUser?.id) {
      setState(() => _error = _t('yourPartnerTurn'));
      return;
    }
    final before = _encode(current);
    setState(() { _busy = true; _error = null; });
    try {
      move(current);
      final nextUser = current.finished
          ? session.currentTurn
          : (session.currentTurn == session.playerOne ? session.playerTwo : session.playerOne);
      final next = await _service.submitState(
        gameId: session.id,
        expectedVersion: session.version,
        state: _encode(current),
        nextTurn: nextUser,
        winner: current.finished
            ? (current.winner == 0 ? session.playerOne : session.playerTwo)
            : null,
      );
      if (!mounted) return;
      setState(() => _session = next);
    } catch (e) {
      if (mounted) {
        setState(() {
          _rules = _decode(before);
          _error = e.toString().contains('STALE_GAME_STATE')
              ? _t('stale')
              : e.toString();
        });
        await _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _suitColor(DoveSuit? suit) => switch (suit) {
    DoveSuit.coral => const Color(0xFFE66D75),
    DoveSuit.ocean => const Color(0xFF3678C8),
    DoveSuit.leaf => const Color(0xFF39966B),
    DoveSuit.sun => const Color(0xFFE0A52F),
    null => const Color(0xFF55466E),
  };

  Future<DoveSuit?> _chooseSuit() async => showDialog<DoveSuit>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(_t('chooseColor')),
      content: Wrap(spacing: 8, children: DoveSuit.values.map((s) => InkWell(
        onTap: () => Navigator.pop(ctx, s),
        child: CircleAvatar(backgroundColor: _suitColor(s), child: Text(_suitName(s), style: const TextStyle(color: Colors.white, fontSize: 10))),
      )).toList()),
    ),
  );


  String _suitName(DoveSuit suit) => _t(switch (suit) {
    DoveSuit.coral => 'coral', DoveSuit.ocean => 'ocean', DoveSuit.leaf => 'leaf', DoveSuit.sun => 'sun',
  });

  String _cardLabel(DoveCard card) => switch (card.kind) {
    DoveCardKind.number => '${card.number ?? 0}',
    DoveCardKind.skip => _lang == 'tr' ? 'ATLA' : _lang == 'de' ? 'AUS' : _lang == 'es' ? 'SALTA' : _lang == 'fr' ? 'SAUT' : 'SKIP',
    DoveCardKind.reverse => _lang == 'tr' ? 'TERS' : _lang == 'de' ? 'WECH' : _lang == 'es' ? 'REV' : _lang == 'fr' ? 'INV' : 'REV',
    DoveCardKind.drawTwo => '+2',
    DoveCardKind.wild => _lang == 'es' ? 'COMODÍN' : 'WILD',
    DoveCardKind.wildDrawFour => '+4',
  };

  Future<void> _showRules() async {
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .82),
        decoration: const BoxDecoration(color: Color(0xFF173B34), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        child: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 12, 24, 28), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: Color(0x66FFF4DD), borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 18),
            Row(children: [const Icon(Icons.menu_book_rounded, color: Color(0xFFE4BD76), size: 28), const SizedBox(width: 10), Expanded(child: Text(_t('rules'), style: const TextStyle(color: Color(0xFFFFF4DD), fontSize: 24, fontWeight: FontWeight.w900)))]),
            const SizedBox(height: 18),
            _ruleLine('01', _t('ruleIntro')),
            _ruleLine('02', _t('ruleMatch')),
            _ruleLine('03', _t('ruleDraw')),
            _ruleLine('04', _t('ruleSpecial')),
            _ruleLine('05', _t('ruleWild')),
            _ruleLine('06', _t('ruleWin')),
          ],
        ))),
      ),
    );
  }

  Widget _ruleLine(String number, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 34, height: 34, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0x26E4BD76), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0x80E4BD76))), child: Text(number, style: const TextStyle(color: Color(0xFFE4BD76), fontWeight: FontWeight.w900))),
      const SizedBox(width: 12),
      Expanded(child: Padding(padding: const EdgeInsets.only(top: 4), child: Text(text, style: const TextStyle(color: Color(0xFFFFF4DD), height: 1.4, fontSize: 14)))),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final rules = _rules;
    final userId = context.watch<AuthProvider>().profile?.id ?? Supabase.instance.client.auth.currentUser?.id;
    if (session == null) return Scaffold(appBar: AppBar(title: const Text('DOVE DECK'), actions: [IconButton(tooltip: _t('refresh'), onPressed: _load, icon: const Icon(Icons.refresh))]), body: Center(child: _error == null ? Text(_t('loading')) : Text(_error!)));
    final myIndex = userId == session.playerOne ? 0 : 1;
    final myTurn = session.currentTurn == userId;
    return Scaffold(
      backgroundColor: const Color(0xFF102B28),
      appBar: AppBar(title: const Text('DOVE DECK'), backgroundColor: const Color(0xFF102B28), foregroundColor: const Color(0xFFF7F1E4), actions: [IconButton(tooltip: _t('rules'), onPressed: _showRules, icon: const Icon(Icons.menu_book_rounded, color: Color(0xFFE4BD76))), IconButton(tooltip: _t('refresh'), onPressed: _load, icon: const Icon(Icons.refresh))]),
      body: SafeArea(child: rules == null
        ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.style, size: 64, color: Color(0xFF55466E)),
            const SizedBox(height: 12),
            Text(session.isWaiting ? _t('waiting') : '${_t('status')}: ${session.status.toUpperCase()}', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (session.isWaiting) Text(
              _t('readyLobby'),
              textAlign: TextAlign.center,
            ),
            if (session.isWaiting) FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(_t('backLobby')),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
          ])))
        : Column(children: [
          const SizedBox(height: 10),
          Text(session.isFinished ? (session.winner == userId ? _t('youWin') : _t('gameOver')) : myTurn ? _t('yourTurn') : _t('partnerTurn'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1.4, color: Color(0xFFF7F1E4))),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _pile(_t('drawPile'), rules.drawPile.length, const Color(0xFF55466E)),
            const SizedBox(width: 18),
            _pile(_t('discardPile'), rules.discardPile.length, _suitColor(rules.topCard.suit), label: _cardLabel(rules.topCard)),
          ]),
          if (rules.chosenSuit != null) Padding(padding: const EdgeInsets.all(6), child: Text('${_t('activeColor')}: ${_suitName(rules.chosenSuit!)}')),
          if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 8),
          Text('${_t('partnerHand')}  ·  ${rules.hands[1-myIndex].length}'),
          const Divider(color: Color(0x33FFFFFF)),
          Expanded(child: Align(alignment: Alignment.bottomCenter, child: SizedBox(height: 220, child: SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(18, 12, 18, 18), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: rules.hands[myIndex].asMap().entries.map((entry) { final card = entry.value; final index = entry.key;
            final enabled = myTurn && !_busy && !session.isFinished && rules.currentPlayer == myIndex && rules.canPlay(card);
            return InkWell(
              onTap: enabled ? () async {
                DoveSuit? suit;
                if (card.isWild) { suit = await _chooseSuit(); if (suit == null || !mounted) return; }
                await _saveMove((r) => r.play(card.id, wildSuit: suit));
              } : null,
              child: Transform.translate(offset: Offset(0, index.isEven ? 8 : 0), child: Transform.rotate(angle: (index - (rules.hands[myIndex].length - 1) / 2) * 0.035, child: Container(width: 82, height: 142, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_suitColor(card.suit).withValues(alpha: .96), _suitColor(card.suit)]), borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFFFF4DC), width: 2.5), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 7))]), child: Stack(alignment: Alignment.center, children: [Transform.rotate(angle: -.35, child: Container(width: 56, height: 100, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(40), border: Border.all(color: Colors.white.withValues(alpha: .75), width: 2)))), Text(_cardLabel(card), style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900, shadows: [Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(1, 2))])), Positioned(top: 8, left: 10, child: Text(_cardLabel(card), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900))), Positioned(bottom: 8, right: 10, child: Icon(Icons.favorite_rounded, size: 13, color: Colors.white.withValues(alpha: .85)))])))),
            );
          }).toList()))))),
          Padding(padding: const EdgeInsets.all(14), child: Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: myTurn && !_busy && !rules.mustPassAfterDraw && !session.isFinished ? () => _saveMove((r) => r.draw()) : null, icon: const Icon(Icons.add), label: Text(_t('draw')))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(onPressed: myTurn && !_busy && rules.mustPassAfterDraw && !session.isFinished ? () => _saveMove((r) => r.pass()) : null, icon: const Icon(Icons.skip_next), label: Text(_t('pass')))),
          ])),
          if (_busy) const LinearProgressIndicator(),
        ]),
      ),
    );
  }

  Widget _pile(String title, int count, Color color, {String? label}) => Column(children: [
    Container(width: 94, height: 132, decoration: BoxDecoration(gradient: LinearGradient(colors: [color, color.withValues(alpha: .72)]), borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFFFF4DC), width: 2.5), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 14, offset: Offset(0, 7))]), child: Center(child: Container(width: 70, height: 106, decoration: BoxDecoration(borderRadius: BorderRadius.circular(38), border: Border.all(color: Colors.white.withValues(alpha: .7), width: 2)), child: Center(child: Text(label ?? '♡\\n$count', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 23))))),
    const SizedBox(height: 5), Text('$title ($count)', style: const TextStyle(fontSize: 11, color: Color(0xFFE8E1D4), fontWeight: FontWeight.w800, letterSpacing: 1.1)),
  ]);
}
