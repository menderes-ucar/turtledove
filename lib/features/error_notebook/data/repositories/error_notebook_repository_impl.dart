import '../../domain/entities/error_item.dart';
import '../../domain/repositories/error_notebook_repository.dart';
import '../datasources/error_notebook_remote_datasource.dart';
class ErrorNotebookRepositoryImpl implements ErrorNotebookRepository {
  final ErrorNotebookRemoteDataSource remote;
  const ErrorNotebookRepositoryImpl(this.remote);
  @override Future<List<ErrorItem>> list( {
    bool? resolved
  })=>remote.list(resolved:resolved);
  @override Future<void> resolve(String id)=>remote.resolve(id);
  @override Future<void> reopen(String id)=>remote.reopen(id);
  @override Future<void> updateNote(String id,String? note)=>remote.updateNote(id,note);
}
