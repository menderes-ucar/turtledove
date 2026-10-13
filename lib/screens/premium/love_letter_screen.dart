import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/auth_provider.dart';
import '../../services/love_letter_service.dart';
import '../../localization/app_strings.dart';

class LoveLetterScreen extends StatefulWidget {
  const LoveLetterScreen({Key? key}) : super(key: key);

  @override
  State<LoveLetterScreen> createState() => _LoveLetterScreenState();
}

class _LoveLetterScreenState extends State<LoveLetterScreen> {
  final letterCtrl = TextEditingController();
  DateTime? scheduledDate;
  bool isComposing = false;
  bool _isSending = false;
  late final LoveLetterService _service;
  Stream<List<LoveLetter>> _lettersStream = const Stream<List<LoveLetter>>.empty();
  final Map<String, Future<String>> _nameRequests = {};
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _service = LoveLetterService(Supabase.instance.client);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final partnerId = context.read<AuthProvider>().profile?.pairedWith;
    _lettersStream = userId == null || partnerId == null || partnerId.isEmpty
        ? const Stream<List<LoveLetter>>.empty()
        : _service.getLettersStream(userId, partnerId);
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    letterCtrl.dispose();
    super.dispose();
  }

  String _dateTime(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final initialDate = scheduledDate != null && scheduledDate!.isAfter(now)
        ? scheduledDate!
        : now;
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;

    final initialTime = scheduledDate != null
        ? TimeOfDay.fromDateTime(scheduledDate!)
        : TimeOfDay.fromDateTime(now.add(const Duration(minutes: 5)));
    final time = await showTimePicker(context: context, initialTime: initialTime);
    if (time == null || !mounted) return;

    final combined = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!combined.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).t('letter_time_future'))),
      );
      return;
    }
    setState(() => scheduledDate = combined);
  }

  Future<String> _senderName(String userId) {
    return _nameRequests.putIfAbsent(userId, () => _service.getProfileName(userId));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final profile = auth.profile;
    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final partnerId = profile.pairedWith;
    if (partnerId == null || partnerId.isEmpty) {
      return Scaffold(
        appBar: null,
        body: Center(child: Text(AppStrings.of(context).t('bestie_area_start'))),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).t('letter_screen_title'))),
      body: isComposing
          ? _buildComposer(profile.id, partnerId)
          : _buildLetterList(profile.id),
    );
  }

  Widget _buildComposer(String userId, String partnerId) {
    final scheduleText = scheduledDate == null
        ? AppStrings.of(context).t('send_now')
        : AppStrings.of(context).t('schedule_send').replaceFirst('{date}', _dateTime(scheduledDate!));

    return Column(
      children: [
        Expanded(
          child: TextField(
            controller: letterCtrl,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration:  InputDecoration(
              hintText: AppStrings.of(context).t('write_letter_hint'),
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(20),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.schedule_rounded),
                      label: Text(scheduleText, overflow: TextOverflow.ellipsis),
                      onPressed: _pickSchedule,
                    ),
                  ),
                  if (scheduledDate != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: AppStrings.of(context).t('scheduled_remove'),
                      onPressed: () => setState(() => scheduledDate = null),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() {
                        isComposing = false;
                        scheduledDate = null;
                      }),
                      child: Text(AppStrings.of(context).t('letter_cancel')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      icon: _isSending
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded),
                      label: Text(AppStrings.of(context).t('letter_send')),
                      onPressed: _isSending
                          ? null
                          : () async {
                              final content = letterCtrl.text.trim();
                              if (content.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(AppStrings.of(context).t('letter_empty_error'))),
                                );
                                return;
                              }
                              final wasScheduled = scheduledDate != null;
                              setState(() => _isSending = true);
                              try {
                                await _service.sendLetter(
                                  userId,
                                  partnerId,
                                  content,
                                  scheduledFor: scheduledDate,
                                );
                                if (!mounted) return;
                                letterCtrl.clear();
                                setState(() {
                                  scheduledDate = null;
                                  isComposing = false;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      wasScheduled ? AppStrings.of(context).t('letter_scheduled') : AppStrings.of(context).t('letter_sent'),
                                    ),
                                  ),
                                );
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('${AppStrings.of(context).t('letter_send_failed')}: $e')),
                                  );
                                }
                              } finally {
                                if (mounted) setState(() => _isSending = false);
                              }
                            },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLetterList(String userId) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<LoveLetter>>(
            stream: _lettersStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text(AppStrings.of(context).t('letters_failed')));
              }
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

              final now = DateTime.now();
              final letters = snapshot.data!.where((letter) {
                final scheduled = letter.scheduledFor?.toLocal();
                if (scheduled == null) return true;
                // The sender can see a scheduled letter; the receiver sees it only when due.
                return letter.senderId == userId || !scheduled.isAfter(now);
              }).toList();

              if (letters.isEmpty) {
                return Center(child: Text(AppStrings.of(context).t('no_letters_yet')));
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                itemCount: letters.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final letter = letters[i];
                  final mine = letter.senderId == userId;
                  final scheduled = letter.scheduledFor?.toLocal();
                  final preview = letter.content.length > 100
                      ? '${letter.content.substring(0, 100)}…'
                      : letter.content;
                  final time = scheduled != null && scheduled.isAfter(now)
                      ? '${AppStrings.of(context).t('schedule_send').replaceFirst('{date}', _dateTime(scheduled))}'
                      : _dateTime(letter.createdAt);

                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(14),
                      leading: CircleAvatar(
                        radius: 24,
                        child: Text(mine ? '✍️' : '💌', style: const TextStyle(fontSize: 22)),
                      ),
                      title: FutureBuilder<String>(
                        future: _senderName(letter.senderId),
                        builder: (context, snap) => Text(
                          mine ? 'Sen → ${_safeName(snap.data)}' : '${_safeName(snap.data)} → Sen',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('$time\n$preview', maxLines: 3, overflow: TextOverflow.ellipsis),
                      ),
                      trailing: !letter.isRead && letter.receiverId == userId
                          ? const Icon(Icons.mark_email_unread_rounded)
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: () => _showLetterDetail(letter, userId),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.edit_rounded),
                label: Text(AppStrings.of(context).t('new_letter')),
                onPressed: () => setState(() => isComposing = true),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _safeName(String? value) => value == null || value.trim().isEmpty ? AppStrings.of(context).partner : value;

  Future<void> _showLetterDetail(LoveLetter letter, String userId) async {
    if (letter.receiverId == userId && !letter.isRead) {
      try {
        await _service.markAsRead(letter.id);
      } catch (_) {}
    }
    if (!mounted) return;

    final sender = await _senderName(letter.senderId);
    if (!mounted) return;
    final scheduled = letter.scheduledFor?.toLocal();

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Text('💌', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 10),
            Expanded(child: Text(mineTitle(letter, userId))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${AppStrings.of(context).t('sender')}: $sender'),
              const SizedBox(height: 4),
              Text('${AppStrings.of(context).t('date')}: ${_dateTime(scheduled ?? letter.createdAt)}'),
              const Divider(height: 24),
              Text(letter.content, style: const TextStyle(fontSize: 17, height: 1.55)),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(AppStrings.of(context).close))],
      ),
    );
  }

  String mineTitle(LoveLetter letter, String userId) =>
      letter.senderId == userId ? AppStrings.of(context).t('sent_letter') : AppStrings.of(context).t('received_letter');
}
