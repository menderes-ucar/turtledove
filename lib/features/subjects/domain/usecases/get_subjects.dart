import '../entities/subject.dart';
import '../repositories/subjects_repository.dart';
class GetSubjects {
  final SubjectsRepository repository;
  const GetSubjects(this.repository);
  Future<List<Subject>> call()=>repository.getSubjects();
}
