import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/conversation_topic_model.dart';

class ConversationTopicService {
  final SupabaseClient client;
  ConversationTopicService(this.client);

  Stream<List<ConversationTopic>> streamTopics() => client.from('conversation_topics').stream(primaryKey:['id']).order('created_at').map((rows)=>rows.map((r)=>ConversationTopic.fromMap(Map<String,dynamic>.from(r))).toList());

  Stream<List<ConversationTopicProgress>> streamProgress(String userId) => client.from('conversation_topic_progress').stream(primaryKey:['topic_id','user_id']).eq('user_id', userId).map((rows)=>rows.map((r)=>ConversationTopicProgress.fromMap(Map<String,dynamic>.from(r))).toList());

  Future<void> saveProgress({required String userId, required String topicId, required bool asked, required String answer}) async {
    await client.from('conversation_topic_progress').upsert({'topic_id':topicId,'user_id':userId,'is_asked':asked,'answer':answer.trim().isEmpty ? null : answer.trim(),'answered_at':answer.trim().isEmpty ? null : DateTime.now().toUtc().toIso8601String()});
  }

  Future<void> addTopic({required String userId, required String prompt}) async {
    final text=prompt.trim(); if(text.isEmpty) return;
    await client.from('conversation_topics').insert({'category':'conversation','slug':'custom-${DateTime.now().microsecondsSinceEpoch}','prompt_tr':text,'prompt_en':text,'prompt_de':text,'prompt_es':text,'prompt_fr':text,'created_by':userId});
  }
}
