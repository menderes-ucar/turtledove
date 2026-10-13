class Question {
  final String id;
  final String subjectId;
  final String questionText;
  final String? imageUrl;
  final String optionA;
  final String optionB;
  final String optionC;
  final String optionD;
  final String? optionE;
  final String? correctOption;
  final String? explanation;
  final int difficultyLevel;
  final String? source;
  final int? year;
  const Question( {
    required this.id,
    required this.subjectId,
    required this.questionText,
    this.imageUrl,
    required this.optionA,
    required this.optionB,
    required this.optionC,
    required this.optionD,
    this.optionE,
    this.correctOption,
    this.explanation,
    required this.difficultyLevel,
    this.source,
    this.year,
  });
  String getOptionText(String option) {
    switch (option.toUpperCase()) {
      case 'A': return optionA;
      case 'B': return optionB;
      case 'C': return optionC;
      case 'D': return optionD;
      case 'E': return optionE ?? '';
      default: return '';
    }
  }
  String getDifficultyLabel() => const {
    1: 'Çok Kolay', 2: 'Kolay', 3: 'Orta', 4: 'Zor', 5: 'Çok Zor',
  }
  [difficultyLevel] ?? 'Bilinmiyor';
}
