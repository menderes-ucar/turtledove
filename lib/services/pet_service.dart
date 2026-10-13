import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/pet_model.dart';
import 'notification_service.dart';

class PetService {
  final SupabaseClient client;

  PetService(this.client);

  Stream<PetModel?> watchPet(String userId) {
    return client
        .from('shared_pets')
        .stream(primaryKey: ['id'])
        .map((rows) {
      final matches = rows.where((row) {
        final m = Map<String, dynamic>.from(row);

        return m['user_a_id'] == userId ||
            m['user_b_id'] == userId;
      }).toList();

      if (matches.isEmpty) {
        return null;
      }

      matches.sort(
            (a, b) => (b['updated_at'] ?? '')
            .toString()
            .compareTo(
          (a['updated_at'] ?? '').toString(),
        ),
      );

      return PetModel.fromMap(
        Map<String, dynamic>.from(matches.first),
      );
    });
  }

  Future<PetModel?> getPet(String userId) async {
    _assertUser(userId);

    final result = await client.rpc(
      'get_shared_pet',
      params: {
        'p_user_id': userId,
      },
    );

    if (result == null) {
      return null;
    }

    if (result is List && result.isEmpty) {
      return null;
    }

    final row = result is List
        ? result.first
        : result;

    return PetModel.fromMap(
      Map<String, dynamic>.from(row as Map),
    );
  }

  Future<PetModel> createPet({
    required String userId,
    required String name,
    required String species,
    required String breed,
  }) async {
    _assertUser(userId);

    final normalizedName = name.trim();

    if (normalizedName.length < 2 ||
        normalizedName.length > 18) {
      throw const FormatException(
        'Pet name must be between 2 and 18 characters',
      );
    }

    const speciesList = {
      'cat',
      'dog',
      'rabbit',
      'bird',
      'hamster',
      'fox',
    };

    if (!speciesList.contains(species)) {
      throw const FormatException(
        'Unsupported pet species',
      );
    }

    final result = await client.rpc(
      'create_shared_pet',
      params: {
        'p_name': normalizedName,
        'p_species': species,
        'p_breed': breed,
        'p_pet_id': const Uuid().v4(),
      },
    );

    final row = result is List
        ? result.first
        : result;

    final pet = PetModel.fromMap(
      Map<String, dynamic>.from(row as Map),
    );

    // Notify partner that a shared pet has been created.
    try {
      final profile = await client
          .from('profiles')
          .select('paired_with')
          .eq('id', userId)
          .maybeSingle();

      final partnerId =
      profile?['paired_with']?.toString();

      if (partnerId != null && partnerId.isNotEmpty) {
        await NotificationService(client).create(
          userId: partnerId,
          title: 'Yeni ortak evcil hayvan',
          body: '$normalizedName artık sizin ortak evcil hayvanınız.',
          type: 'pet',
          data: {
            'action': 'created',
            'pet_id': pet.id,
            'pet_name': normalizedName,
          },
        );
      }
    } catch (e) {
      debugPrint(
        'Pet creation notification skipped: $e',
      );
    }

    return pet;
  }

  Future<PetModel> performAction({
    required String userId,
    required String petId,
    required String action,
  }) async {
    _assertUser(userId);

    const actions = {
      'feed',
      'bath',
      'clean',
      'nails',
      'toilet',
      'play',
      'sleep',
      'love',
    };

    if (!actions.contains(action)) {
      throw const FormatException(
        'Unsupported pet action',
      );
    }

    final result = await client.rpc(
      'perform_pet_action',
      params: {
        'p_pet_id': petId,
        'p_action': action,
      },
    );

    final row = result is List
        ? result.first
        : result;

    final pet = PetModel.fromMap(
      Map<String, dynamic>.from(row as Map),
    );

    // Notify partner about the pet action.
    try {
      final profile = await client
          .from('profiles')
          .select('paired_with')
          .eq('id', userId)
          .maybeSingle();

      final partnerId =
      profile?['paired_with']?.toString();

      if (partnerId != null && partnerId.isNotEmpty) {
        await NotificationService(client).create(
          userId: partnerId,
          title: 'Pet aktivitesi',
          body: 'Ortak evcil hayvanınız için "$action" yapıldı.',
          type: 'pet',
          data: {
            'action': action,
            'action_name': action,
            'pet_id': pet.id,
          },
        );
      }
    } catch (e) {
      debugPrint(
        'Pet notification skipped: $e',
      );
    }

    return pet;
  }

  void _assertUser(String userId) {
    final current = client.auth.currentUser;

    if (current == null || current.id != userId) {
      throw const AuthException(
        'You must be signed in to use the pet',
      );
    }
  }
}