import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/mood_model.dart';
import '../../providers/mood_provider.dart';
import '../../services/mood_service.dart';
import '../../localization/app_strings.dart';

class MoodScreen extends StatefulWidget {
  const MoodScreen({Key? key}) : super(key: key);

  @override
  State<MoodScreen> createState() => _MoodScreenState();
}

class _MoodScreenState extends State<MoodScreen> {
  int selectedMood = 3;
  String selectedCategory = 'general';
  final noteCtrl = TextEditingController();
  bool _isSaving = false;
  late final MoodProvider _provider;

  @override
  void initState() {
    super.initState();
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('MoodScreen requires an authenticated user');
    }
    _provider = MoodProvider(
      moodService: MoodService(client),
      userId: userId,
    );
  }

  Widget _buildDataError(String error) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.of(context).t('mood_history_failed'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(AppStrings.of(context).t('check_database')),
          const SizedBox(height: 6),
          Text(error, maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _provider.dispose();
    noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _provider,
      child: Scaffold(
        appBar: AppBar(title: Text(AppStrings.of(context).mood)),
        body: Consumer<MoodProvider>(
          builder: (ctx, provider, _) => SingleChildScrollView(
            child: Column(
              children: [
                if (provider.streamError != null)
                  _buildDataError(provider.streamError!),

                // MOOD STATS
                if (provider.moods.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(AppStrings.of(context).t('last_30_days'), style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                Text('${provider.averageMood.toStringAsFixed(1)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                                Text(AppStrings.of(context).t('average')),
                              ],
                            ),
                            Column(
                              children: [
                                Text('${provider.stats['highest'] ?? 0}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                                Text(AppStrings.of(context).t('mood_best')),
                              ],
                            ),
                            Column(
                              children: [
                                Text('${provider.moods.length}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                                Text(AppStrings.of(context).t('entries')),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                // ADD MOOD SECTION
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppStrings.of(context).t('how_are_you'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 20),
                      // MOOD SLIDER
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(5, (i) {
                          final mood = i + 1;
                          return GestureDetector(
                            onTap: () => setState(() => selectedMood = mood),
                            child: Column(
                              children: [
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: selectedMood == mood
                                        ? Theme.of(context).primaryColor
                                        : Colors.grey.shade200,
                                  ),
                                  child: Center(
                                    child: Text(
                                      MoodEntry(
                                        id: '',
                                        userId: '',
                                        mood: mood,
                                        createdAt: DateTime.now(),
                                      ).getEmoji(),
                                      style: const TextStyle(fontSize: 32),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  MoodEntry(
                                    id: '',
                                    userId: '',
                                    mood: mood,
                                    createdAt: DateTime.now(),
                                  ).getMoodText(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: selectedMood == mood ? Theme.of(context).primaryColor : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 20),
                      // CATEGORY
                      DropdownButton<String>(
                        value: selectedCategory,
                        isExpanded: true,
                        items: [
                          DropdownMenuItem(value: 'general', child: Text('${AppStrings.of(context).t('category_general')} 😐')),
                          DropdownMenuItem(value: 'relationship', child: Text('${AppStrings.of(context).t('category_relationship')} 💑')),
                          DropdownMenuItem(value: 'work', child: Text('${AppStrings.of(context).t('category_work')} 💼')),
                          DropdownMenuItem(value: 'health', child: Text('${AppStrings.of(context).t('category_health')} 💪')),
                          DropdownMenuItem(value: 'family', child: Text('${AppStrings.of(context).t('category_family')} 👨‍👩‍👧')),
                        ],
                        onChanged: (v) => setState(() => selectedCategory = v!),
                      ),
                      const SizedBox(height: 16),
                      // NOTE
                      TextField(
                        controller: noteCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: AppStrings.of(context).t('note_optional'),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // SUBMIT
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : () async {
                            setState(() => _isSaving = true);
                            try {
                              await provider.addMood(
                                selectedMood,
                                note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                                category: selectedCategory,
                              );
                              if (!mounted) return;
                              noteCtrl.clear();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(AppStrings.of(context).t('mood_saved'))),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('${AppStrings.of(context).t('save')}: $e')),
                              );
                            } finally {
                              if (mounted) setState(() => _isSaving = false);
                            }
                          },
                          child: _isSaving
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(AppStrings.of(context).save),
                        ),
                      ),
                    ],
                  ),
                ),

                // MOOD HISTORY
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppStrings.of(context).t('interactionHistory'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      ...provider.moods.take(10).map((mood) => ListTile(
                        leading: Text(mood.getEmoji(), style: const TextStyle(fontSize: 24)),
                        title: Text(mood.getMoodText()),
                        subtitle: Text(mood.note ?? mood.category ?? AppStrings.of(context).t('category_general')),
                        trailing: Text(
                          '${mood.createdAt.day}/${mood.createdAt.month}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      )).toList(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
