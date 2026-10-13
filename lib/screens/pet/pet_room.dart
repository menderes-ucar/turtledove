import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'pet_localization.dart';

enum PetRoom { home, bathroom, bedroom, kitchen }

class PetRoomScene extends StatelessWidget {
  final PetRoom room;
  final String species;
  final Widget pet;
  final String title;
  final String subtitle;

  const PetRoomScene({
    super.key,
    required this.room,
    required this.species,
    required this.pet,
    required this.title,
    required this.subtitle,
  });

  String get _asset => switch (room) {
        PetRoom.home => 'assets/pet_rooms/playroom.png',
        PetRoom.bathroom => 'assets/pet_rooms/bathroom.png',
        PetRoom.bedroom => 'assets/pet_rooms/bedroom.png',
        PetRoom.kitchen => 'assets/pet_rooms/kitchen.png',
      };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 430,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(_asset, fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(.06), Colors.black.withOpacity(.18)],
                ),
              ),
            ),
            Positioned(top: 16, left: 16, right: 16, child: _RoomHeader(title: title, subtitle: subtitle)),
            Positioned(left: 0, right: 0, bottom: -4, child: Center(child: pet)),
            Positioned(
              right: 14,
              bottom: 14,
              child: _SpeciesBadge(species: species),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _RoomHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(.30),
            border: Border.all(color: Colors.white.withOpacity(.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(.86), fontSize: 11)),
            ],
          ),
        ),
      );
}

class _SpeciesBadge extends StatelessWidget {
  final String species;
  const _SpeciesBadge({required this.species});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.25),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(.18)),
        ),
        child: Text(
          '${switch (species) {
            'cat' => '🐱',
            'dog' => '🐶',
            'rabbit' => '🐰',
            'bird' => '🐦',
            'hamster' => '🐹',
            'fox' => '🦊',
            'snake' => '🐍',
            _ => '🐾',
          }} ${PetStrings.of(context).speciesName(species)}',
          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
        ),
      );
}
