import '../entities/subject.dart';
abstract class SubjectsRepository {
  Future<List<Subject>> getSubjects();
}
