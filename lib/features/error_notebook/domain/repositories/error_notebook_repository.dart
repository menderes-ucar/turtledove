import '../entities/error_item.dart';
abstract class ErrorNotebookRepository {
  Future<List<ErrorItem>> list( {
    bool? resolved
  });
  Future<void> resolve(String id);
  Future<void> reopen(String id);
  Future<void> updateNote(String id,String? note);
}
