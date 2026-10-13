import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/countdown_model.dart';
import '../../providers/countdown_provider.dart';
import '../../services/countdown_service.dart';
import '../../localization/app_strings.dart';

class CountdownScreen extends StatefulWidget {
  const CountdownScreen({Key? key}) : super(key: key);

  @override
  State<CountdownScreen> createState() => _CountdownScreenState();
}

class _CountdownScreenState extends State<CountdownScreen> {
  final titleCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  DateTime? selectedDate;
  String selectedType = 'visit';
  String? selectedEmoji;
  bool _isAdding = false;
  late final CountdownProvider _provider;

  @override
  void initState() {
    super.initState();
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('CountdownScreen requires an authenticated user');
    }
    _provider = CountdownProvider(
      countdownService: CountdownService(client),
      userId: userId,
    );
  }

  @override
  void dispose() {
    _provider.dispose();
    titleCtrl.dispose();
    noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _provider,
      child: Scaffold(
        appBar: AppBar(title: Text(AppStrings.of(context).t('countdown_title'))),
        body: Consumer<CountdownProvider>(
          builder: (ctx, provider, _) => Column(
            children: [
              Expanded(
                child: provider.streamError != null
                    ? _buildDataError(provider.streamError!)
                    : provider.countdowns.isEmpty
                        ? Center(child: Text(AppStrings.of(context).t('no_countdowns'), style: Theme.of(context).textTheme.titleMedium))
                        : ListView.builder(
                        itemCount: provider.countdowns.length,
                        itemBuilder: (_, i) {
                          final cd = provider.countdowns[i];
                          return Card(
                            margin: const EdgeInsets.all(12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${cd.getEmoji()} ${cd.title}',
                                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              cd.isPast ? AppStrings.of(context).t('countdown_finished') : '${cd.daysRemaining} ${AppStrings.of(context).t('days_left')}',
                                              style: TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.bold,
                                                color: cd.isPast ? Colors.grey : Theme.of(context).primaryColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.red),
                                        onPressed: () async {
                                          try {
                                            await provider.deleteCountdown(cd.id);
                                          } catch (e) {
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('${AppStrings.of(context).t('countdown_delete_failed')}: $e')),
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  LinearProgressIndicator(
                                    value: _progressFor(cd),
                                    minHeight: 8,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade300))),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(AppStrings.of(context).t('new_countdown')),
                    onPressed: () => _showAddDialog(ctx, provider),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _progressFor(Countdown countdown) {
    if (countdown.isPast) return 1.0;

    final total = countdown.targetDate.difference(countdown.createdAt).inMilliseconds;
    if (total <= 0) return 0.0;

    final elapsed = DateTime.now().difference(countdown.createdAt).inMilliseconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  Widget _buildDataError(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              AppStrings.of(context).t('countdown_data_failed'),
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.of(context).t('check_premium_tables'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context, CountdownProvider provider) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.of(context).t('new_countdown')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: InputDecoration(labelText: AppStrings.of(context).t('headline')),
              ),
              const SizedBox(height: 16),
              DropdownButton<String>(
                value: selectedType,
                isExpanded: true,
                items: [
                  DropdownMenuItem(value: 'visit', child: Text(AppStrings.of(context).t('visit'))),
                  DropdownMenuItem(value: 'anniversary', child: Text(AppStrings.of(context).t('anniversary'))),
                  DropdownMenuItem(value: 'birthday', child: Text(AppStrings.of(context).t('birthday'))),
                  DropdownMenuItem(value: 'custom', child: Text(AppStrings.of(context).t('custom'))),
                ],
                onChanged: (v) => setState(() => selectedType = v!),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 1)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                  );
                  if (date != null) setState(() => selectedDate = date);
                },
                child: Text(selectedDate == null ? AppStrings.of(context).t('select_date') : '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(AppStrings.of(context).t('letter_cancel'))),
          ElevatedButton(
            onPressed: _isAdding ? null : () async {
              if (titleCtrl.text.trim().isEmpty || selectedDate == null) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStrings.of(context).t('fill_all_fields'))));
                return;
              }
              setState(() => _isAdding = true);
              try {
                await provider.addCountdown(titleCtrl.text.trim(), selectedDate!, selectedType);
                if (!mounted) return;
                titleCtrl.clear();
                selectedDate = null;
                Navigator.pop(context);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${AppStrings.of(context).t('countdown_delete_failed')}: $e')),
                );
              } finally {
                if (mounted) setState(() => _isAdding = false);
              }
            },
            child: _isAdding
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(AppStrings.of(context).t('save')),
          ),
        ],
      ),
    );
  }
}
