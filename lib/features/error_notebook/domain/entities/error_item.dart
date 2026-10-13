class ErrorItem {
  final String id;
  final String questionId;
  final String subjectId;
  final bool resolved;
  final int wrongCount;
  final DateTime lastWrongAt;
  final String? noteText;

  const ErrorItem({
    required this.id,
    required this.questionId,
    required this.subjectId,
    required this.resolved,
    required this.wrongCount,
    required this.lastWrongAt,
    this.noteText,
  });
}
