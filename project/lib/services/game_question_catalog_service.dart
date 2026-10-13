import 'package:supabase_flutter/supabase_flutter.dart';

class GameQuestionCatalogItem {
  final String gameType;
  final String category;
  final String? subcategory;
  final String title;
  final String emoji;
  final int questionCount;

  const GameQuestionCatalogItem({
    required this.gameType,
    required this.category,
    this.subcategory,
    required this.title,
    required this.emoji,
    required this.questionCount,
  });

  factory GameQuestionCatalogItem.fromMap(Map<String, dynamic> map) {
    return GameQuestionCatalogItem(
      gameType: map['game_type']?.toString() ?? '',
      category: map['category']?.toString() ?? '',
      subcategory: map['subcategory']?.toString(),
      title: map['title']?.toString() ?? map['category']?.toString() ?? '',
      emoji: map['emoji']?.toString() ?? '🎮',
      questionCount: (map['question_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class GameQuestionCatalogService {
  final SupabaseClient client;

  GameQuestionCatalogService(this.client);

  Future<List<GameQuestionCatalogItem>> getCatalog(String gameType) async {
    _requireAuthenticatedUser();

    final rows = await client
        .from('game_question_catalog')
        .select()
        .eq('game_type', gameType.trim().toLowerCase())
        .eq('is_active', true)
        .order('sort_order')
        .order('title');

    return rows
        .map((row) => GameQuestionCatalogItem.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<int> getAvailableQuestionCount({
    required String gameType,
    List<String> categories = const <String>[],
    String? category,
    String? subcategory,
  }) async {
    _requireAuthenticatedUser();

    var query = client
        .from('game_questions')
        .select('id')
        .eq('game_type', gameType.trim().toLowerCase())
        .eq('is_active', true);

    final normalizedCategories = categories
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (normalizedCategories.isNotEmpty) {
      query = query.inFilter('category', normalizedCategories);
    } else if (category != null && category.trim().isNotEmpty) {
      query = query.eq('category', category.trim());
    }
    if (subcategory != null && subcategory.trim().isNotEmpty) {
      query = query.eq('subcategory', subcategory.trim());
    }

    final rows = await query;
    return rows.length;
  }

  Future<int> getUnseenQuestionCountForPair({
    required String gameType,
    List<String> categories = const <String>[],
  }) async {
    _requireAuthenticatedUser();
    final userId = client.auth.currentUser!.id;

    final profile = await client
        .from('profiles')
        .select('paired_with')
        .eq('id', userId)
        .maybeSingle();
    final partnerId = profile?['paired_with']?.toString();
    if (partnerId == null || partnerId.isEmpty) {
      throw const AuthException('Game requires a paired partner');
    }

    final normalizedCategories = categories
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);

    final rows = await client.rpc(
      'count_unseen_game_questions_for_pair',
      params: {
        'p_game_type': gameType.trim().toLowerCase(),
        'p_partner_id': partnerId,
        'p_categories': normalizedCategories,
      },
    );

    final count = rows is num
        ? rows.toInt()
        : int.tryParse(rows.toString()) ?? 0;
    return count;
  }

  void _requireAuthenticatedUser() {
    final session = client.auth.currentSession;
    if (session == null || session.accessToken.isEmpty || client.auth.currentUser == null) {
      throw const AuthException('Game requires an active session');
    }
  }
}
