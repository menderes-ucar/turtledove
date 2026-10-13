import 'package:flutter/foundation.dart';
import '../../domain/entities/subject.dart';
import '../../domain/usecases/get_subjects.dart';
class SubjectsProvider extends ChangeNotifier {
  final GetSubjects getSubjects;
  SubjectsProvider(this.getSubjects);
  List<Subject> subjects=[];
  bool loading=false;
  String? error;
  Future<void> load() async {
    loading=true;
    error=null;
    notifyListeners();
    try {
      subjects=await getSubjects();
    } catch(e) {
      error='Dersler yüklenemedi.';
    } finally {
      loading=false;
      notifyListeners();
    }
  }
}
