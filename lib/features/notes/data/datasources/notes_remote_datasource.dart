import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/note_model.dart';

class NotesRemoteDataSource {
  final SupabaseClient client;

  const NotesRemoteDataSource(this.client);

  Future<List<NoteModel>> list() async {
    final response = await client
        .from('notes')
        .select(
          'id,subject_id,title,content,created_at,updated_at',
        )
        .order(
          'updated_at',
          ascending: false,
        );

    return (response as List)
        .map(
          (item) => NoteModel.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false);
  }

  Future<NoteModel> create({
    String? subjectId,
    required String title,
    required String content,
  }) async {
    final response = await client
        .from('notes')
        .insert({
          'subject_id': subjectId,
          'title': title,
          'content': content,
        })
        .select(
          'id,subject_id,title,content,created_at,updated_at',
        )
        .single();

    return NoteModel.fromJson(
      Map<String, dynamic>.from(response),
    );
  }

  Future<void> update(
    String id, {
    required String title,
    required String content,
    String? subjectId,
  }) async {
    await client
        .from('notes')
        .update({
          'title': title,
          'content': content,
          'subject_id': subjectId,
        })
        .eq('id', id);
  }

  Future<void> delete(String id) async {
    await client
        .from('notes')
        .delete()
        .eq('id', id);
  }
}
