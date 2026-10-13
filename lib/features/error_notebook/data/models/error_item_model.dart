import '../../domain/entities/error_item.dart';

class ErrorItemModel extends ErrorItem {
  const ErrorItemModel({
    required super.id,
    required super.questionId,
    required super.subjectId,
    required super.resolved,
    required super.wrongCount,
    required super.lastWrongAt,
    super.noteText,
  });

  factory ErrorItemModel.fromJson(Map<String, dynamic> json) {
    return ErrorItemModel(
      id: json['id'] as String,
      questionId: json['question_id'] as String,
      subjectId: json['subject_id'] as String,
      resolved: json['resolved'] as bool? ?? false,
      wrongCount: (json['wrong_count'] as num?)?.toInt() ?? 1,
      lastWrongAt: DateTime.parse(json['last_wrong_at'].toString()),
      noteText: json['note_text'] as String?,
    );
  }
}
