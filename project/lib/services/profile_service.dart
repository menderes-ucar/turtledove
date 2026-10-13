import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class ProfileService {
  final SupabaseClient client;
  ProfileService(this.client);

  static const allowedStatuses = {'online', 'offline', 'away'};

  Future<void> updateProfile({
    required String userId,
    required String username,
    required String status,
  }) async {
    final currentUser = client.auth.currentUser;
    if (currentUser == null || currentUser.id != userId) {
      throw const AuthException('You must be signed in to update your profile');
    }

    final normalizedUsername = username.trim();
    final normalizedStatus = status.trim().toLowerCase();

    if (normalizedUsername.length < 3 || normalizedUsername.length > 20) {
      throw const FormatException('Username must be between 3 and 20 characters');
    }

    if (!allowedStatuses.contains(normalizedStatus)) {
      throw const FormatException('Invalid status');
    }

    await client.from('profiles').update({
      'username': normalizedUsername,
      'status': normalizedStatus,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }

  Future<String> uploadAvatar(XFile file, String userId) async {
    final currentUser = client.auth.currentUser;
    if (currentUser == null || currentUser.id != userId) {
      throw const AuthException('You must be signed in to upload an avatar');
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const FormatException('Selected image is empty');
    }

    final fileName = '${const Uuid().v4()}.jpg';
    final path = '$userId/$fileName';

    await client.storage.from('avatars').uploadBinary(path, bytes);

    final publicUrl = client.storage.from('avatars').getPublicUrl(path);

    await client.from('profiles').update({
      'avatar_url': publicUrl,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);

    return publicUrl;
  }

  Future<void> updateLastSeen(String userId) async {
    final currentUser = client.auth.currentUser;
    if (currentUser == null || currentUser.id != userId) return;

    await client.from('profiles').update({
      'last_seen_at': DateTime.now().toIso8601String(),
      'status': 'online',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }
}
