class ConversationTopic {
  final String id;
  final String category;
  final String slug;
  final String promptTr;
  final String promptEn;
  final String promptDe;
  final String promptEs;
  final String promptFr;
  final String? createdBy;

  const ConversationTopic({required this.id, required this.category, required this.slug, required this.promptTr, required this.promptEn, required this.promptDe, required this.promptEs, required this.promptFr, this.createdBy});

  factory ConversationTopic.fromMap(Map<String,dynamic> m) => ConversationTopic(
    id: '${m['id']}', category: '${m['category']}', slug: '${m['slug']}',
    promptTr: '${m['prompt_tr'] ?? ''}', promptEn: '${m['prompt_en'] ?? ''}', promptDe: '${m['prompt_de'] ?? ''}', promptEs: '${m['prompt_es'] ?? ''}', promptFr: '${m['prompt_fr'] ?? ''}',
    createdBy: m['created_by']?.toString(),
  );

  String prompt(String code) => switch(code) { 'tr'=>promptTr, 'de'=>promptDe, 'es'=>promptEs, 'fr'=>promptFr, _=>promptEn };
}

class ConversationTopicProgress {
  final String topicId;
  final String userId;
  final bool asked;
  final String answer;
  const ConversationTopicProgress({required this.topicId, required this.userId, required this.asked, required this.answer});
  factory ConversationTopicProgress.fromMap(Map<String,dynamic> m) => ConversationTopicProgress(topicId:'${m['topic_id']}', userId:'${m['user_id']}', asked:m['is_asked']==true, answer:'${m['answer'] ?? ''}');
}
