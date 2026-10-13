class GameCategory {
  final String id;
  final String title;
  final String emoji;
  final List<String> subcategories;

  const GameCategory({
    required this.id,
    required this.title,
    required this.emoji,
    this.subcategories = const [],
  });
}
