import '../../domain/entities/subject.dart';
import '../../domain/repositories/subjects_repository.dart';
import '../datasources/subjects_remote_datasource.dart';
class SubjectsRepositoryImpl implements SubjectsRepository {
  final SubjectsRemoteDataSource remote;
  const SubjectsRepositoryImpl(this.remote);
  @override Future<List<Subject>> getSubjects()=>remote.getSubjects();
}
