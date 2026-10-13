import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/subject_model.dart';

class SubjectsRemoteDataSource {
  final SupabaseClient client;

  const SubjectsRemoteDataSource(this.client);

  Future<List<SubjectModel>> getSubjects() async {
    final response = await client
        .from('subjects')
        .select(
          'id,name,description,icon_name,difficulty_order',
        )
        .order('difficulty_order');

    return (response as List)
        .map(
          (item) => SubjectModel.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false);
  }
}
