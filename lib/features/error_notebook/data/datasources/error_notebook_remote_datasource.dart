import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/error_item_model.dart';

class ErrorNotebookRemoteDataSource {
  final SupabaseClient client;

  const ErrorNotebookRemoteDataSource(this.client);

  Future<List<ErrorItemModel>> list({
    bool? resolved,
  }) async {
    var query = client
        .from('error_notebook')
        .select(
          'id,question_id,subject_id,resolved,wrong_count,last_wrong_at,note_text',
        );

    if (resolved != null) {
      query = query.eq('resolved', resolved);
    }

    final response = await query.order(
      'last_wrong_at',
      ascending: false,
    );

    return (response as List)
        .map(
          (item) => ErrorItemModel.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false);
  }

  Future<void> resolve(String id) async {
    await client
        .from('error_notebook')
        .update({
          'resolved': true,
        })
        .eq('id', id);
  }

  Future<void> reopen(String id) async {
    await client
        .from('error_notebook')
        .update({
          'resolved': false,
        })
        .eq('id', id);
  }

  Future<void> updateNote(
    String id,
    String? note,
  ) async {
    await client
        .from('error_notebook')
        .update({
          'note_text': note,
        })
        .eq('id', id);
  }
}
