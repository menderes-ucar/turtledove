import '../../domain/entities/note.dart';
import '../../domain/repositories/notes_repository.dart';
import '../datasources/notes_remote_datasource.dart';
class NotesRepositoryImpl implements NotesRepository {
  final NotesRemoteDataSource remote;
  const NotesRepositoryImpl(this.remote);
  @override Future<List<Note>> list()=>remote.list();
  @override Future<Note> create( {
    String? subjectId,required String title,required String content
  })=>remote.create(subjectId:subjectId,title:title,content:content);
  @override Future<void> update(String id, {
    String? subjectId,required String title,required String content
  })=>remote.update(id,subjectId:subjectId,title:title,content:content);
  @override Future<void> delete(String id)=>remote.delete(id);
}
