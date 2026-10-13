import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/pet_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pet_provider.dart';
import '../../services/pet_service.dart';
import 'pet_localization.dart';
import 'pet_avatar_3d.dart';
import 'pet_room.dart';

class PetScreen extends StatelessWidget {
  const PetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final userId = auth.profile?.id;
    final partner = auth.profile?.pairedWith;
    if (userId == null || partner == null || partner.isEmpty) {
      return Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(PetStrings.of(context).sharedPetInfo, textAlign: TextAlign.center))));
    }
    return ChangeNotifierProvider(
      create: (_) => PetProvider(service: context.read<PetService>(), userId: userId),
      child: const _PetView(scaffold: true),
    );
  }
}

class PetTabScreen extends StatelessWidget {
  const PetTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final userId = auth.profile?.id;
    final partner = auth.profile?.pairedWith;
    if (userId == null || partner == null || partner.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(PetStrings.of(context).sharedPetInfo, textAlign: TextAlign.center)));
    }
    return ChangeNotifierProvider(
      create: (_) => PetProvider(service: context.read<PetService>(), userId: userId),
      child: const _PetView(scaffold: false),
    );
  }
}

class _PetView extends StatefulWidget {
  final bool scaffold;
  const _PetView({required this.scaffold});
  @override State<_PetView> createState() => _PetViewState();
}

class _PetViewState extends State<_PetView> {
  PetRoom _room = PetRoom.home;
  PetAnimation _animation = PetAnimation.idle;
  String? _sceneAction;
  Timer? _sceneTimer;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _sceneTimer?.cancel();
    super.dispose();
  }

  void _setScene(String action) {
    final room = switch (action) {
      'bath' || 'clean' || 'nails' || 'toilet' => PetRoom.bathroom,
      'sleep' => PetRoom.bedroom,
      'feed' => PetRoom.kitchen,
      _ => PetRoom.home,
    };
    final animation = switch (action) {
      'bath' => PetAnimation.bath,
      'clean' => PetAnimation.clean,
      'nails' => PetAnimation.nails,
      'toilet' => PetAnimation.toilet,
      'feed' => PetAnimation.feed,
      'play' => PetAnimation.play,
      'sleep' => PetAnimation.sleep,
      'love' => PetAnimation.love,
      _ => PetAnimation.idle,
    };
    setState(() { _room = room; _animation = animation; _sceneAction = action; });
    _sceneTimer?.cancel();
    _sceneTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() { _animation = PetAnimation.idle; _sceneAction = null; });
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PetProvider>();
    final pet = state.pet;
    final strings = PetStrings.of(context);
    final content = state.loading
        ? const Center(child: CircularProgressIndicator())
        : pet == null
            ? _CreatePet(state: state)
            : _PetHome(pet: pet, animation: _animation, room: _room, action: _sceneAction, onAction: _performAction, onRoomSelected: _selectRoom);

    if (!widget.scaffold) {
      return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(children: [
            Expanded(child: Text(pet == null ? '🐾 ${strings.title}' : '${pet.speciesEmoji} ${pet.name}', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
          ]),
        ),
        Expanded(child: content),
      ]);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(pet == null ? '🐾 ${strings.title}' : '${pet.speciesEmoji} ${pet.name}'),
      ),
      body: content,
    );
  }

  void _selectRoom(PetRoom room) {
    _sceneTimer?.cancel();
    setState(() {
      _room = room;
      _animation = PetAnimation.idle;
      _sceneAction = null;
    });
  }

  Future<void> _performAction(String action) async {
    final state = context.read<PetProvider>();
    if (state.busy) return;
    _setScene(action);
    try {
      await state.action(action);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(PetStrings.of(context).actionError(e))));
    }
  }


}

class _CreatePet extends StatefulWidget {
  final PetProvider state;
  const _CreatePet({required this.state});
  @override State<_CreatePet> createState() => _CreatePetState();
}

class _CreatePetState extends State<_CreatePet> {
  final name = TextEditingController();
  String species = 'cat';
  String breed = 'ragdoll';
  static const speciesList = <String, String>{'cat':'🐱','dog':'🐶','rabbit':'🐰','bird':'🐦','hamster':'🐹','fox':'🦊','snake':'🐍'};
  static const breeds = <String, List<String>>{
    'cat': ['ragdoll','british_shorthair','siamese'],
    'dog': ['golden_retriever','corgi','siberian_husky'],
    'rabbit': ['holland_lop','lionhead','rex'],
    'bird': ['cockatiel','budgerigar','lovebird'],
    'hamster': ['syrian','dwarf','roborovski'],
    'fox': ['red_fox','arctic_fox','fennec'],
    'snake': ['ball_python','corn_snake','king_snake'],
  };
  @override void dispose() { name.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    const SizedBox(height: 18),
    const Icon(Icons.pets_rounded, size: 62),
    const SizedBox(height: 12),
    Text(PetStrings.of(context).sharedPet, textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
    const SizedBox(height: 8),
    Text(PetStrings.of(context).sharedPetInfo, textAlign: TextAlign.center),
    const SizedBox(height: 22),
    TextField(controller: name, maxLength: 18, decoration: InputDecoration(labelText: PetStrings.of(context).petName, border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.badge_outlined))),
    const SizedBox(height: 12),
    Text(PetStrings.of(context).speciesLabel, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
    const SizedBox(height: 8),
    Wrap(spacing: 10, runSpacing: 10, children: speciesList.entries.map((e) => ChoiceChip(label: Text('${e.value} ${PetStrings.of(context).speciesName(e.key)}'), selected: species == e.key, onSelected: (_) => setState(() { species = e.key; breed = breeds[e.key]!.first; }))).toList()),
    const SizedBox(height: 16),
    Text(PetStrings.of(context).breedLabel, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
    const SizedBox(height: 8),
    Wrap(spacing: 10, runSpacing: 10, children: breeds[species]!.map((b) => ChoiceChip(label: Text(_breedName(b)), selected: breed == b, onSelected: (_) => setState(() => breed = b))).toList()),
    const SizedBox(height: 24),
    FilledButton.icon(onPressed: widget.state.busy ? null : () async { try { await widget.state.create(name: name.text, species: species, breed: breed); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(PetStrings.of(context).actionError(e)))); } }, icon: const Icon(Icons.auto_awesome), label: Text(PetStrings.of(context).create)),
    if (widget.state.error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(widget.state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
  ]);
}

class _RoomSelector extends StatelessWidget {
  final PetRoom current;
  final ValueChanged<PetRoom> onSelected;
  const _RoomSelector({required this.current, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final strings = PetStrings.of(context);
    final rooms = <(PetRoom, String, IconData)>[
      (PetRoom.home, strings.roomPlayShort, Icons.toys_rounded),
      (PetRoom.bathroom, strings.roomCareShort, Icons.shower_rounded),
      (PetRoom.bedroom, strings.roomSleepShort, Icons.bed_rounded),
      (PetRoom.kitchen, strings.roomFoodShort, Icons.restaurant_rounded),
    ];
    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: rooms.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final r = rooms[i];
          return ChoiceChip(
            avatar: Icon(r.$3, size: 18),
            label: Text(r.$2),
            selected: current == r.$1,
            onSelected: (_) => onSelected(r.$1),
          );
        },
      ),
    );
  }
}

String _breedName(String value) => value.split('_').map((e) => e.isEmpty ? e : e[0].toUpperCase() + e.substring(1)).join(' ');

class _PetHome extends StatelessWidget {
  final PetModel pet;
  final PetAnimation animation;
  final PetRoom room;
  final String? action;
  final Future<void> Function(String action) onAction;
  final ValueChanged<PetRoom> onRoomSelected;
  const _PetHome({required this.pet, required this.animation, required this.room, required this.action, required this.onAction, required this.onRoomSelected});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PetProvider>();
    final strings = PetStrings.of(context);
    final roomTitle = switch (room) { PetRoom.home => strings.roomHome, PetRoom.bathroom => strings.roomBath, PetRoom.bedroom => strings.roomSleep, PetRoom.kitchen => strings.roomKitchen };
    final roomSubtitle = switch (room) { PetRoom.home => strings.roomHomeSubtitle, PetRoom.bathroom => strings.roomBathSubtitle, PetRoom.bedroom => strings.roomSleepSubtitle, PetRoom.kitchen => strings.roomKitchenSubtitle };
    return RefreshIndicator(
      onRefresh: state.refresh,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 30), children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 480),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          child: PetRoomScene(
            key: ValueKey('${room.name}:${action ?? 'idle'}'),
            room: room,
            species: pet.species,
            title: roomTitle,
            subtitle: roomSubtitle,
            pet: PetAvatar3D(species: pet.species, breed: pet.breed, animation: animation, size: 235, sleeping: animation == PetAnimation.sleep),
          ),
        ),
        const SizedBox(height: 12),
        _RoomSelector(current: room, onSelected: onRoomSelected),
        const SizedBox(height: 12),
        _PetProgress(pet: pet),
        const SizedBox(height: 12),
        _StatsGrid(pet: pet),
        const SizedBox(height: 12),
        _ActionGrid(state: state, onAction: onAction),
        const SizedBox(height: 12),
        _BondCard(pet: pet),
      ]),
    );
  }
}

class _PetProgress extends StatelessWidget {
  final PetModel pet;
  const _PetProgress({required this.pet});
  @override
  Widget build(BuildContext context) {
    final s = PetStrings.of(context);
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      Row(children: [Expanded(child: Text(pet.name, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900))), Text('${s.level} ${pet.level}', style: const TextStyle(fontWeight: FontWeight.w800))]),
      const SizedBox(height: 8),
      Row(children: [Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: pet.levelProgress, minHeight: 10))), const SizedBox(width: 10), Text(pet.level >= PetModel.maxLevel ? s.maxLevel : s.xp(pet.xp), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))]),
      const SizedBox(height: 8),
      Row(children: [Text(_stage(context, pet.stageKey)), const Spacer(), const Icon(Icons.monetization_on_rounded, size: 18), const SizedBox(width: 4), Text('${pet.coins}', style: const TextStyle(fontWeight: FontWeight.w800))]),
    ])));
  }
}

class _StatsGrid extends StatelessWidget {
  final PetModel pet;
  const _StatsGrid({required this.pet});
  @override
  Widget build(BuildContext context) => GridView.count(crossAxisCount: 3, childAspectRatio: 1.32, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 8, crossAxisSpacing: 8, children: [
    _Stat('🍖', PetStrings.of(context).hunger, pet.hunger), _Stat('🛁', PetStrings.of(context).hygiene, pet.hygiene), _Stat('⚡', PetStrings.of(context).energy, pet.energy),
    _Stat('🎾', PetStrings.of(context).fun, pet.fun), _Stat('❤️', PetStrings.of(context).health, pet.health), _Stat('🚽', PetStrings.of(context).toilet, pet.toilet),
  ]);
}

class _Stat extends StatelessWidget {
  final String icon, label; final int value;
  const _Stat(this.icon, this.label, this.value);
  @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(8), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(icon, style: const TextStyle(fontSize: 19)), const SizedBox(height: 3), Text('$value%', style: const TextStyle(fontWeight: FontWeight.w900)), Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10))])));
}

class _ActionGrid extends StatelessWidget {
  final PetProvider state;
  final Future<void> Function(String) onAction;

  const _ActionGrid({required this.state, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final strings = PetStrings.of(context);
    final actions = <(String, String, String)>[
      ('feed', '🍖', strings.feed),
      ('bath', '🛁', strings.bath),
      ('clean', '🧽', strings.clean),
      ('nails', '✂️', strings.nails),
      ('toilet', '🚽', strings.toiletAction),
      ('play', '🎾', strings.play),
      ('sleep', '😴', strings.sleep),
      ('love', '❤️', strings.love),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.carePlay, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: .82,
              children: actions.map((action) {
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: state.busy ? null : () => onAction(action.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.all(3),
                    padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 3),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(action.$2, style: const TextStyle(fontSize: 25)),
                        const SizedBox(height: 4),
                        Text(action.$3, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _BondCard extends StatelessWidget {
  final PetModel pet;
  const _BondCard({required this.pet});
  @override Widget build(BuildContext context) => Card(child: ListTile(leading: const Text('💕', style: TextStyle(fontSize: 30)), title: Text(PetStrings.of(context).sharedBond), subtitle: Text('${PetStrings.of(context).affection(pet.affection)} • ${PetStrings.of(context).coins(pet.coins)}'), trailing: const Icon(Icons.auto_awesome)));
}

String _stage(BuildContext context, String key) { final s = PetStrings.of(context); return switch (key) { 'baby' => s.baby, 'child' => s.child, 'young' => s.young, 'teen' => s.teen, 'adult' => s.adult, 'mature' => s.mature, 'senior' => s.senior, _ => s.title }; }
