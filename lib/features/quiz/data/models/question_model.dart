import '../../domain/entities/question.dart';
class QuestionModel extends Question {
  const QuestionModel( {
    required super.id, required super.subjectId, required super.questionText,
    super.imageUrl, required super.optionA, required super.optionB,
    required super.optionC, required super.optionD, super.optionE,
    super.correctOption, super.explanation, required super.difficultyLevel,
    super.source, super.year,
  });
  factory QuestionModel.fromJson(Map<String, dynamic> json) => QuestionModel(
  id: json['id'] as String? ?? '',
  subjectId: json['subject_id'] as String? ?? '',
  questionText: json['question_text'] as String? ?? '',
  imageUrl: json['image_url'] as String?,
  optionA: json['option_a'] as String? ?? '',
  optionB: json['option_b'] as String? ?? '',
  optionC: json['option_c'] as String? ?? '',
  optionD: json['option_d'] as String? ?? '',
  optionE: json['option_e'] as String?,
  // These fields are intentionally nullable. Public question RPC must not return them.
  correctOption: (json['correct_option'] as String?)?.toUpperCase(),
  explanation: json['explanation'] as String?,
  difficultyLevel: (json['difficulty_level'] as num?)?.toInt() ?? 3,
  source: json['source'] as String?,
  year: (json['year'] as num?)?.toInt(),
  );
}
