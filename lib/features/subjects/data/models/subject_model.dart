import '../../domain/entities/subject.dart';

class SubjectModel extends Subject {
  const SubjectModel({
    required super.id,
    required super.name,
    super.description,
    super.iconName,
    super.difficultyOrder,
  });

  factory SubjectModel.fromJson(Map<String, dynamic> json) {
    return SubjectModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      iconName: json['icon_name'] as String?,
      difficultyOrder: (json['difficulty_order'] as num?)?.toInt() ?? 0,
    );
  }
}
