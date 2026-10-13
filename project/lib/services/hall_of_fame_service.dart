import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/hall_of_fame_photo_model.dart';

class HallOfFameService {
  final SupabaseClient client;
  HallOfFameService(this.client);

  static const bucket = 'hall-of-fame';
  static const maxPhotos = 10;
  static const categories = {'aura', 'meme', 'mood'};

  Stream<List<HallOfFamePhoto>> streamPhotos(String userId) => client
      .from('hall_of_fame_photos')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .asyncMap((rows) async {
        final result = <HallOfFamePhoto>[];
        for (final r in rows) {
          final photo = HallOfFamePhoto.fromMap(Map<String, dynamic>.from(r));
          try {
            final signed = await client.storage.from(bucket).createSignedUrl(photo.storagePath, 60 * 60);
            result.add(photo.copyWith(publicUrl: signed));
          } catch (_) {
            result.add(photo);
          }
        }
        return result.where((p) => p.ownerId == userId || p.partnerId == userId).toList();
      });

  Future<int> countOwned(String userId) async {
    final rows = await client
        .from('hall_of_fame_photos')
        .select('id')
        .eq('owner_id', userId);
    return (rows as List).length;
  }

  Future<List<HallOfFamePhoto>> addFromGallery({
    required String userId,
    required String category,
  }) async {
    if (!categories.contains(category)) throw ArgumentError('Invalid category');
    final current = await countOwned(userId);
    final remaining = maxPhotos - current;
    if (remaining <= 0) throw StateError('HALL_OF_FAME_LIMIT');

    final picked = await ImagePicker().pickMultiImage(
      imageQuality: 100,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (picked.isEmpty) return [];

    final files = picked.take(remaining).toList();
    final uploaded = <HallOfFamePhoto>[];
    String? partnerId;
    try {
      final profile = await client
          .from('profiles')
          .select('paired_with')
          .eq('id', userId)
          .maybeSingle();
      partnerId = profile?['paired_with']?.toString();
    } catch (_) {
      partnerId = null;
    }

    for (final file in files) {
      final original = await file.readAsBytes();
      if (original.isEmpty) continue;
      final compressed = await _compress(original);
      final bytes = compressed.isEmpty ? original : compressed;
      final id = const Uuid().v4();
      final path = '$userId/$id.webp';

      await client.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/webp',
              upsert: false,
            ),
          );
      const url = '';
      final row = await client
          .from('hall_of_fame_photos')
          .insert({
            'owner_id': userId,
            'partner_id': partnerId,
            'category': category,
            'storage_path': path,
            'public_url': url,
          })
          .select()
          .single();
      uploaded.add(HallOfFamePhoto.fromMap(Map<String, dynamic>.from(row)));
    }
    return uploaded;
  }

  Future<void> updateNote({required String photoId, required String note}) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('Not signed in');
    final photo = await client.from('hall_of_fame_photos').select('owner_id,partner_id,storage_path').eq('id', photoId).maybeSingle();
    if (photo == null || (photo['owner_id'] != userId && photo['partner_id'] != userId)) {
      throw const AuthException('Not allowed');
    }
    await client.from('hall_of_fame_photos').update({
      'note': note.trim().isEmpty ? null : note.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', photoId);
  }

  Future<void> deletePhoto(HallOfFamePhoto photo) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null || userId != photo.ownerId) throw const AuthException('Not allowed');
    await client.from('hall_of_fame_photos').delete().eq('id', photo.id).eq('owner_id', userId);
    try {
      await client.storage.from(bucket).remove([photo.storagePath]);
    } catch (_) {
      // Keep the database deletion successful even if storage cleanup is retried later.
    }
  }

  Future<Uint8List> _compress(Uint8List input) async {
    final result = await FlutterImageCompress.compressWithList(
      input,
      minWidth: 1200,
      minHeight: 1200,
      quality: 82,
      format: CompressFormat.webp,
      keepExif: false,
    );
    return Uint8List.fromList(result);
  }
}
