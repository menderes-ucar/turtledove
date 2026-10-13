class GameQuestion {
  final String id;
  final String gameType;
  final String category;
  final String? subcategory;
  final String prompt;
  final String questionType;
  final List<String> options;
  final String? correctAnswer;
  final String difficulty;

  const GameQuestion({
    required this.id,
    required this.gameType,
    required this.category,
    required this.subcategory,
    required this.prompt,
    required this.questionType,
    required this.options,
    required this.correctAnswer,
    required this.difficulty,
  });

  factory GameQuestion.fromMap(Map<String, dynamic> map) {
    final rawOptions = map['options'];
    final options = rawOptions is List
        ? rawOptions.map((item) => item.toString()).toList(growable: false)
        : const <String>[];

    return GameQuestion(
      id: map['id'] as String,
      gameType: (map['game_type'] ?? '') as String,
      category: (map['category'] ?? '') as String,
      subcategory: map['subcategory']?.toString(),
      prompt: (map['prompt'] ?? '') as String,
      questionType: (map['question_type'] ?? 'question') as String,
      options: options,
      correctAnswer: map['correct_answer']?.toString(),
      difficulty: (map['difficulty'] ?? 'medium') as String,
    );
  }
}
