import 'package:flutter/foundation.dart';
import '../../domain/entities/note.dart';
import '../../domain/repositories/notes_repository.dart';
class NotesProvider extends ChangeNotifier {
  final NotesRepository repository;
  NotesProvider(this.repository);
  List<Note> notes=[];
  bool loading=false;
  String? error;
  Future<void> load()async {
    loading=true;
    notifyListeners();
    try {
      notes=await repository.list();
      error=null;
    }
    catch(e) {
      error='Notlar yüklenemedi.';
    }
    finally {
      loading=false;
      notifyListeners();
    }
  }
  Future<void> save( {
    String? id,String? subjectId,required String title,required String content
  })async {
    if(id==null)await repository.create(subjectId:subjectId,title:title,content:content);
    else await repository.update(id,subjectId:subjectId,title:title,content:content);
    await load();
  }
  Future<void> delete(String id)async {
    await repository.delete(id);
    await load();
  }
}
