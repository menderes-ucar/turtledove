import '../entities/note.dart';
abstract class NotesRepository {
  Future<List<Note>> list();
  Future<Note> create( {
    String? subjectId,required String title,required String content
  });
  Future<void> update(String id, {
    String? subjectId,required String title,required String content
  });
  Future<void> delete(String id);
}
