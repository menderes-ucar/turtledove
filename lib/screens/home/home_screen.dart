import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';

import '../../models/message_model.dart';
import '../../models/todo_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../localization/app_strings.dart';
import '../../services/chat_service.dart';
import '../../services/todo_service.dart';
import '../../services/interaction_service.dart';
import '../../services/notification_service.dart';
import '../../services/call_service.dart';
import '../../services/love_letter_service.dart';
import '../profile/profile_screen.dart';
import '../../models/interaction_model.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;
  StreamSubscription<List<Interaction>>? _interactionSubscription;
  Interaction? _activeInteraction;
  String? _lastInteractionId;
  Timer? _interactionTimer;
  StreamSubscription<List<AppNotification>>? _notificationSubscription;
  StreamSubscription<List<AppNotification>>? _callNotificationSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _callSessionSubscription;
  String? _lastLoveLetterNotificationId;
  String? _lastCallNotificationId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listenForInteractions();
      _listenForLoveLetters();
      _listenForIncomingCalls();
      _listenForIncomingCallSessions();
    });
  }

  void _listenForIncomingCallSessions() {
    final profile = context.read<AuthProvider>().profile;
    if (profile == null) return;

    _callSessionSubscription?.cancel();
    _callSessionSubscription = Supabase.instance.client
        .from('call_sessions')
        .stream(primaryKey: ['id'])
        .eq('receiver_id', profile.id)
        .listen((rows) async {
      if (!mounted || rows.isEmpty) return;

      final now = DateTime.now().toUtc();
      for (final row in rows) {
        final status = row['status']?.toString();
        if (status != 'ringing') continue;

        final callId = row['id']?.toString();
        final callerId = row['caller_id']?.toString();
        if (callId == null || callId.isEmpty || callerId == null || callerId.isEmpty) continue;

        final createdAt = DateTime.tryParse(row['created_at']?.toString() ?? '')?.toUtc();
        if (createdAt != null && now.difference(createdAt) > const Duration(seconds: 90)) continue;

        if (GoRouter.of(context).routerDelegate.currentConfiguration.uri.path.contains('/call/')) continue;

        final callService = context.read<CallService>();
        if (!callService.claimIncomingCallUi(callId)) continue;

        String? callerName;
        try {
          final caller = await Supabase.instance.client
              .from('profiles')
              .select('username')
              .eq('id', callerId)
              .maybeSingle();
          callerName = caller?['username']?.toString().trim();
        } catch (_) {}

        if (!mounted) {
          callService.releaseIncomingCallUi(callId);
          return;
        }

        final query = <String, String>{'partnerId': callerId};
        if (callerName != null && callerName.isNotEmpty) {
          query['callerName'] = callerName;
        }
        final queryString = '?${query.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
        context.go('/home/call/$callId/receiver$queryString');
        break;
      }
    }, onError: (e) => debugPrint('Incoming call session listener: $e'));
  }

  void _listenForLoveLetters() {
    final profile = context.read<AuthProvider>().profile;
    if (profile == null) return;
    _notificationSubscription?.cancel();
    _notificationSubscription = context
        .read<NotificationService>()
        .stream(profile.id)
        .listen((items) {
      if (!mounted || items.isEmpty) return;
      final love = items.where((item) => item.type == 'love_letter').toList();
      if (love.isEmpty) return;
      final latest = love.first;
      if (_lastLoveLetterNotificationId == null) {
        _lastLoveLetterNotificationId = latest.id;
        return;
      }
      if (latest.id == _lastLoveLetterNotificationId) return;
      _lastLoveLetterNotificationId = latest.id;
      final letterId = latest.data['letter_id']?.toString();
      if (letterId == null || letterId.isEmpty) return;
      unawaited(_showIncomingLoveLetter(letterId));
    }, onError: (e) => debugPrint('Love letter notification listener: $e'));
  }

  void _listenForIncomingCalls() {
    final profile = context.read<AuthProvider>().profile;
    if (profile == null) return;

    // When BESTIE is already open, the durable notification row is the wake-up
    // path. This listener is deliberately separate from FCM/native handling so
    // foreground calls do not depend on Android notification presentation.
    _callNotificationSubscription?.cancel();
    _callNotificationSubscription = context.read<NotificationService>().stream(profile.id).listen((items) async {
      if (!mounted || items.isEmpty) return;
      final calls = items.where((item) => item.type == 'call').toList();
      if (calls.isEmpty) return;
      final latest = calls.first;
      // Do not discard the first emitted call notification. A ringing call
      // may have been created just before this screen subscribed (for example
      // when the app returns to foreground). The call-session row below is
      // authoritative, and claimIncomingCallUi() prevents duplicate routes.
      if (latest.id == _lastCallNotificationId) return;
      _lastCallNotificationId = latest.id;

      final callId = latest.data['call_id']?.toString();
      final callerId = latest.data['caller_id']?.toString();
      if (callId == null || callId.isEmpty || callerId == null || callerId.isEmpty) return;
      if (GoRouter.of(context).routerDelegate.currentConfiguration.uri.path.contains('/call/')) return;

      final service = context.read<CallService>();
      final session = await service.getCallSession(callId);
      if (!mounted || session?['status']?.toString() != 'ringing') return;
      if (session?['receiver_id']?.toString() != profile.id) return;
      if (!service.claimIncomingCallUi(callId)) return;

      final callerName = latest.data['caller_name']?.toString().trim();
      final query = <String, String>{'partnerId': callerId};
      if (callerName != null && callerName.isNotEmpty) query['callerName'] = callerName;
      final queryString = '?${query.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
      if (mounted) context.go('/home/call/$callId/receiver$queryString');
    }, onError: (e) => debugPrint('Incoming call notification listener: $e'));
  }

  Future<void> _showIncomingLoveLetter(String letterId) async {
    try {
      final letter = await LoveLetterService(Supabase.instance.client).getLetter(letterId);
      final currentUser = context.read<AuthProvider>().profile;
      if (currentUser == null || letter.receiverId != currentUser.id) return;
      if (!mounted) return;
      final service = LoveLetterService(Supabase.instance.client);
      final sender = await service.getProfileName(letter.senderId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          child: InkWell(
            borderRadius: BorderRadius.circular(32),
            onTap: () async {
              await service.markAsRead(letter.id);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (!mounted) return;
              await showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  title: Text('💌 $sender'),
                  content: SingleChildScrollView(
                    child: Text(letter.content, style: const TextStyle(fontSize: 17, height: 1.55)),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(AppStrings.of(context).close),
                    ),
                  ],
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('💌', style: TextStyle(fontSize: 120)),
                  SizedBox(height: 12),
                  Text(AppStrings.of(context).loveLetters, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                  SizedBox(height: 6),
                  Text(AppStrings.of(context).incomingLoveLetter, textAlign: TextAlign.center),
                  SizedBox(height: 16),
                  Text(AppStrings.of(context).open, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Incoming love letter overlay failed: $e');
    }
  }

  void _listenForInteractions() {
    final profile = context.read<AuthProvider>().profile;
    if (profile == null) return;
    _interactionSubscription?.cancel();
    _interactionSubscription = context.read<InteractionService>().getInteractionsStream(profile.id, partnerId: profile.pairedWith).listen((items) {
      if (!mounted || items.isEmpty) return;
      final latest = items.first;
      if (latest.senderId == profile.id || latest.id == _lastInteractionId) return;
      _lastInteractionId = latest.id;
      setState(() => _activeInteraction = latest);
      _interactionTimer?.cancel();
      _interactionTimer = Timer(const Duration(milliseconds: 2200), () {
        if (mounted) setState(() => _activeInteraction = null);
      });
    }, onError: (e) => debugPrint('Interaction listener: $e'));
  }

  @override
  void dispose() {
    _interactionSubscription?.cancel();
    _notificationSubscription?.cancel();
    _callNotificationSubscription?.cancel();
    _callSessionSubscription?.cancel();
    _interactionTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.read<AuthProvider>().profile;
    final strings = AppStrings.of(context);

    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final client = Supabase.instance.client;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: _PartnerMoodHeader(
          partnerId: profile.pairedWith,
          onTap: profile.pairedWith == null || profile.pairedWith!.isEmpty
              ? null
              : () => context.push('/home/profile/${profile.pairedWith}'),
        ),
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'theme') _showThemeDialog(context);
              if (value == 'profile') context.push('/profile');
              if (value == 'calls') context.push('/home/call-history');
              if (value == 'notifications') context.push('/home/notifications');
              if (value == 'logout') {
                await context.read<AuthProvider>().signOut();
                if (mounted) context.go('/login');
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'theme', child: Text(strings.theme)),
              PopupMenuItem(value: 'profile', child: Text(strings.profile)),
              PopupMenuItem(value: 'calls', child: Text(strings.callHistory)),
              PopupMenuItem(value: 'notifications', child: Text(strings.notifications)),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'logout', child: Text(strings.logout)),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(profile.id, profile.pairedWith),
          if (_activeInteraction != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: .45, end: 1),
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.elasticOut,
                    builder: (_, scale, __) => Transform.scale(
                      scale: scale,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        if (_activeInteraction!.type == 'infinity')
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.7, end: 1.15),
                            duration: const Duration(milliseconds: 900),
                            curve: Curves.easeInOut,
                            builder: (_, scale, __) => Transform.scale(
                              scale: scale,
                              child: const Text('∞', style: TextStyle(fontSize: 150, fontWeight: FontWeight.w900)),
                            ),
                          )
                        else
                          Text(_activeInteraction!.getEmoji(), style: const TextStyle(fontSize: 110)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(.35), blurRadius: 28, spreadRadius: 4)],
                          ),
                          child: Text(_interactionLabel(_activeInteraction!.type), style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.chat_outlined), selectedIcon: const Icon(Icons.chat_rounded), label: strings.chat),
          NavigationDestination(icon: const Icon(Icons.games_outlined), selectedIcon: const Icon(Icons.games_rounded), label: strings.games),
          NavigationDestination(icon: const Icon(Icons.favorite_outline_rounded), selectedIcon: const Icon(Icons.favorite_rounded), label: strings.relationship),
          NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: strings.profile),
        ],
      ),

    );
  }

  Widget _buildBody(String userId, String? partnerId) {
    if ((partnerId == null || partnerId.isEmpty) && _tabIndex != 4) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.favorite_outline,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              SizedBox(height: 16),
              Text(
                AppStrings.of(context).startUsingTogether,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                AppStrings.of(context).pairFirst,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => context.go('/pairing'),
                icon: const Icon(Icons.link),
                label: Text(AppStrings.of(context).pair),
              ),
            ],
          ),
        ),
      );
    }

    switch (_tabIndex) {
      case 0:
        return ChatTabScreen(
          userId: userId,
          partnerId: partnerId!,
          onOpenTodo: () => _showTodoSheet(userId, partnerId),
          onCall: () => _startCall(userId, partnerId),
        );
      case 1:
        return const GamesTabScreen();
      case 2:
        return  RelationshipHubScreen();
      case 3:
        return const ProfileScreen();
      default:
        return const SizedBox();
    }
  }

  Future<void> _startCall(String userId, String? partnerId) async {
    if (partnerId == null || partnerId.isEmpty) return;
    try {
      final service = context.read<CallService>();
      await service.connect(userId: userId, partnerId: partnerId);
      final callId = await service.createCall();
      if (mounted) context.go('/home/call/$callId/caller');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.of(context).callFailed}: $e')),
        );
      }
    }
  }

  String _interactionLabel(String type) {
    final strings = AppStrings.of(context);
    return switch (type) {
      'hug' => '${strings.hug} 💕',
      'kiss' => '${strings.kiss} 💋',
      'nudge' => '${strings.nudge} 👉',
      'miss_you' => '${strings.missYou} 🥺',
      'infinity' => '${strings.forever} ∞',
      _ => strings.interactions,
    };
  }

  Future<void> _showTodoSheet(String userId, String? partnerId) async {
    if (partnerId == null || partnerId.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .78,
        child: TodoTabScreen(userId: userId, partnerId: partnerId),
      ),
    );
  }

  void _showThemeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.of(context).theme),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Consumer<ThemeProvider>(
              builder: (ctx, theme, _) => Row(
                children: [
                  Text(context.read<ThemeProvider>().isDark ? AppStrings.of(context).darkTheme : AppStrings.of(context).lightTheme),
                  Spacer(),
                  Switch(value: theme.isDark, onChanged: (_) => theme.toggleDarkMode()),
                ],
              ),
            ),
            SizedBox(height: 20),
            Text(AppStrings.of(context).color),
            const SizedBox(height: 10),
            Consumer<ThemeProvider>(
              builder: (ctx, theme, _) => Wrap(
                spacing: 10,
                children: List.generate(
                  5,
                  (i) => GestureDetector(
                    onTap: () => theme.setColor(i),
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: ThemeProvider.colors[i],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorIndex == i ? Colors.white : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(AppStrings.of(context).close))],
      ),
    );
  }
}


class _PartnerMoodHeader extends StatefulWidget {
  final String? partnerId;
  final VoidCallback? onTap;

  const _PartnerMoodHeader({required this.partnerId, this.onTap});

  @override
  State<_PartnerMoodHeader> createState() => _PartnerMoodHeaderState();
}

class _PartnerMoodHeaderState extends State<_PartnerMoodHeader> {
  Stream<List<Map<String, dynamic>>>? _moodStream;
  Future<Map<String, dynamic>?>? _profileFuture;
  RealtimeChannel? _moodChannel;
  StreamSubscription<List<AppNotification>>? _moodNotificationSubscription;
  int? _partnerMood;
  Map<String, dynamic>? _partnerProfile;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant _PartnerMoodHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.partnerId != widget.partnerId) _bind();
  }

  void _bind() {
    _moodChannel?.unsubscribe();
    _moodChannel = null;
    _moodNotificationSubscription?.cancel();
    _moodNotificationSubscription = null;
    _partnerMood = null;
    _partnerProfile = null;
    final id = widget.partnerId;
    if (id == null || id.isEmpty) {
      _profileFuture = Future.value(null);
      _moodStream = null;
      _partnerMood = null;
      _partnerProfile = null;
      return;
    }

    final client = Supabase.instance.client;
    _profileFuture = client
        .from('profiles')
        .select('username,avatar_url')
        .eq('id', id)
        .maybeSingle()
        .then((row) {
          _partnerProfile = row;
          if (mounted) setState(() {});
          return row;
        });

    _loadLatestPartnerMood(id);

    // Push-created notifications are already part of BESTIE's realtime
    // notification stream. Use the mood payload as a second, independent
    // realtime path so the chat header updates even when Postgres Changes for
    // mood_entries has not been enabled in an older Supabase project.
    final notificationService = context.read<NotificationService>();
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId != null && currentUserId.isNotEmpty) {
      _moodNotificationSubscription = notificationService.stream(currentUserId).listen((items) {
        if (!mounted || widget.partnerId != id) return;
        for (final item in items) {
          if (item.type != 'mood') continue;
          final rawMood = item.data['mood'];
          final mood = rawMood is num
              ? rawMood.toInt()
              : int.tryParse(rawMood?.toString() ?? '');
          if (mood != null && mood >= 1 && mood <= 5) {
            setState(() => _partnerMood = mood);
            break;
          }
        }
      }, onError: (error) {
        debugPrint('BESTIE partner mood notification stream failed: $error');
      });
    }

    // Do not depend only on the convenience .stream() query. A dedicated
    // Postgres changes channel updates the header immediately when a new mood
    // row is inserted.
    final channel = client.channel('bestie-partner-mood-$id');
    _moodChannel = channel;
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'mood_entries',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: id,
          ),
          callback: (payload) {
            final row = Map<String, dynamic>.from(payload.newRecord);
            final mood = (row['mood'] as num?)?.toInt();
            if (!mounted) return;
            setState(() => _partnerMood = mood);
          },
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            debugPrint('BESTIE partner mood realtime ready id=$id');
          } else if (status == RealtimeSubscribeStatus.channelError || status == RealtimeSubscribeStatus.timedOut) {
            debugPrint('BESTIE partner mood realtime status=$status error=$error');
          }
        });

    _moodStream = client
        .from('mood_entries')
        .stream(primaryKey: ['id'])
        .eq('user_id', id)
        .order('created_at', ascending: false)
        .map((rows) => rows.map((row) => Map<String, dynamic>.from(row)).toList());
  }

  Future<void> _loadLatestPartnerMood(String id) async {
    try {
      final row = await Supabase.instance.client
          .from('mood_entries')
          .select('mood,created_at')
          .eq('user_id', id)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (!mounted || widget.partnerId != id) return;
      setState(() => _partnerMood = (row?['mood'] as num?)?.toInt());
    } catch (e) {
      debugPrint('BESTIE partner mood load failed: $e');
    }
  }

  String _moodText(AppStrings strings, int? mood) {
    return switch (mood) {
      1 => strings.moodTerrible,
      2 => strings.moodBad,
      3 => strings.moodOkay,
      4 => strings.moodGood,
      5 => strings.moodAmazing,
      _ => strings.moodNone,
    };
  }

  String _moodEmoji(int? mood) {
    return switch (mood) { 1 => '😢', 2 => '😕', 3 => '😐', 4 => '🙂', 5 => '😄', _ => '•' };
  }

  @override
  void dispose() {
    _moodChannel?.unsubscribe();
    _moodChannel = null;
    _moodNotificationSubscription?.cancel();
    _moodNotificationSubscription = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (widget.partnerId == null || widget.partnerId!.isEmpty) {
      return Text(strings.partner, style: const TextStyle(fontWeight: FontWeight.w700));
    }

    return FutureBuilder<Map<String, dynamic>?>(
      future: _profileFuture,
      builder: (context, profileSnap) {
        final data = _partnerProfile ?? profileSnap.data;
        final username = data?['username']?.toString() ?? strings.partner;
        final avatarUrl = data?['avatar_url']?.toString();
        return InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(24),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null || avatarUrl.isEmpty ? const Icon(Icons.person, size: 20) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _moodStream,
                  builder: (context, moodSnap) {
                    final latest = moodSnap.data?.isNotEmpty == true ? moodSnap.data!.first : null;
                    final mood = _partnerMood ?? (latest?['mood'] as num?)?.toInt();
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(username, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('${_moodEmoji(mood)}  ${_moodText(strings, mood)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ChatTabScreen extends StatefulWidget {
  final String userId;
  final String partnerId;
  final VoidCallback onOpenTodo;
  final VoidCallback onCall;

  const ChatTabScreen({
    required this.userId,
    required this.partnerId,
    required this.onOpenTodo,
    required this.onCall,
    Key? key,
  }) : super(key: key);

  @override
  State<ChatTabScreen> createState() => _ChatTabScreenState();
}

class _ChatTabScreenState extends State<ChatTabScreen> {
  late final Stream<List<Message>> _messagesStream;
  final msgCtrl = TextEditingController();
  final AudioRecorder _voiceRecorder = AudioRecorder();
  bool _sending = false;
  bool _recording = false;
  bool _markedAsRead = false;
  String? _recordingPath;
  DateTime? _recordingStartedAt;
  Duration _recordingElapsed = Duration.zero;
  Timer? _recordingTimer;

  @override
  void initState() {
    super.initState();
    _messagesStream = context.read<ChatService>().getMessagesStream(widget.userId, widget.partnerId);
    _markMessagesAsRead();
  }

  Future<void> _markMessagesAsRead() async {
    if (_markedAsRead) return;
    _markedAsRead = true;
    try {
      await context.read<ChatService>().markMessagesAsRead(
        widget.userId,
        widget.partnerId,
      );
    } catch (e) {
      debugPrint('🔴 ChatTabScreen._markMessagesAsRead error: $e');
      _markedAsRead = false;
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    msgCtrl.dispose();
    unawaited(_voiceRecorder.dispose());
    super.dispose();
  }

  Future<void> _startVoiceRecording() async {
    if (_sending || _recording) return;
    try {
      final permitted = await _voiceRecorder.hasPermission();
      if (!permitted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppStrings.of(context).t('voice_permission_denied'))),
          );
        }
        return;
      }

      final directory = await Directory.systemTemp.createTemp('turtle_dove_voice_');
      final path = '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _voiceRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 44100,
        ),
        path: path,
      );
      if (!mounted) {
        await _voiceRecorder.stop();
        return;
      }
      setState(() {
        _recording = true;
        _recordingPath = path;
        _recordingStartedAt = DateTime.now();
        _recordingElapsed = Duration.zero;
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final started = _recordingStartedAt;
        if (!mounted || started == null) {
          timer.cancel();
          return;
        }
        final elapsed = DateTime.now().difference(started);
        if (elapsed >= const Duration(minutes: 2)) {
          unawaited(_stopAndSendVoice());
        } else {
          setState(() => _recordingElapsed = elapsed);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.of(context).t('voice_record_failed')}: $e')),
        );
      }
    }
  }

  Future<void> _stopAndSendVoice() async {
    if (!_recording || _sending) return;
    _recordingTimer?.cancel();
    String? path;
    try {
      path = await _voiceRecorder.stop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.of(context).t('voice_record_failed')}: $e')),
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordingPath = null;
      _recordingStartedAt = null;
      _recordingElapsed = Duration.zero;
      _sending = true;
    });

    try {
      final finalPath = path;
      if (finalPath == null || finalPath.isEmpty || !await File(finalPath).exists()) {
        throw const FormatException('Voice recording file was not created.');
      }
      final url = await context.read<ChatService>().uploadMedia(
        XFile(finalPath, name: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a'),
        widget.userId,
      );
      await context.read<ChatService>().sendMessage(
        widget.userId,
        widget.partnerId,
        null,
        url,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).t('voice_sent'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.of(context).t('voice_send_failed')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _cancelVoiceRecording() async {
    if (!_recording) return;
    _recordingTimer?.cancel();
    try {
      await _voiceRecorder.stop();
    } catch (_) {}
    final path = _recordingPath;
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _recording = false;
        _recordingPath = null;
        _recordingStartedAt = null;
        _recordingElapsed = Duration.zero;
      });
    }
  }

  String _voiceTime(Duration value) =>
      '${value.inMinutes.toString().padLeft(2, '0')}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  Future<void> _pickMedia() async {
    if (_sending) return;
    final picker = ImagePicker();
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(child: Wrap(children: [
        ListTile(leading: Icon(Icons.photo_library_outlined), title: Text(AppStrings.of(ctx).chooseImage), onTap: () => Navigator.pop(ctx, 'image')),
        ListTile(leading: Icon(Icons.video_library_outlined), title: Text(AppStrings.of(ctx).chooseVideo), onTap: () => Navigator.pop(ctx, 'video')),
      ])),
    );
    if (source == null) return;
    final file = source == 'image'
        ? await picker.pickImage(source: ImageSource.gallery, imageQuality: 88)
        : await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 5));
    if (file == null || !mounted) return;
    setState(() => _sending = true);
    try {
      final url = await context.read<ChatService>().uploadMedia(file, widget.userId);
      await context.read<ChatService>().sendMessage(widget.userId, widget.partnerId, null, url);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AppStrings.of(context).mediaSendFailed}: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _send() async {
    final content = msgCtrl.text.trim();
    if (content.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      await context.read<ChatService>().sendMessage(
        widget.userId,
        widget.partnerId,
        content,
        null,
      );
      msgCtrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.of(context).sendFailed}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showInteractions(BuildContext context) async {
    final profile = context.read<AuthProvider>().profile;
    if (profile?.pairedWith == null || profile!.pairedWith!.isEmpty) return;

    final interactionService = context.read<InteractionService>();
    final strings = AppStrings.of(context);
    final types = [
      ('hug', '🫂', strings.hug),
      ('kiss', '💋', strings.kiss),
      ('nudge', '👉', strings.nudge),
      ('miss_you', '🥺', strings.missYou),
      ('infinity', '∞', strings.forever),
    ];

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppStrings.of(context).sendToPartner, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: types.map((item) => ActionChip(
                  avatar: Text(item.$2, style: const TextStyle(fontSize: 20)),
                  label: Text(AppStrings.of(context).t('interaction_${item.$1}')),
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    try {
                      await interactionService.sendInteraction(profile.id, profile.pairedWith!, item.$1);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${AppStrings.of(context).t('interaction_${item.$1}')} ${AppStrings.of(context).sent} 💕')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${AppStrings.of(context).sendFailed}: $e')),
                        );
                      }
                    }
                  },
                )).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ChatPartnerHeader(partnerId: widget.partnerId),
        _ChatQuickActions(
          onTodo: widget.onOpenTodo,
          onCall: widget.onCall,
          onInteraction: () => _showInteractions(context),
        ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Chat wallpaper: intentionally faded so message bubbles and text
              // remain the visual focus. The original artwork is preserved.
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 1,
                    child: Image.asset(
                      'assets/images/chat_background.jpeg',
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              ),
              StreamBuilder<List<Message>>(
                stream: _messagesStream,
                builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _HomeStateView(
                  icon: Icons.cloud_off_outlined,
                  title: AppStrings.of(context).chatLoadFailed,
                  message: AppStrings.of(context).checkConnection,
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final messages = snapshot.data!;
              if (messages.isEmpty) {
                return _HomeStateView(
                  icon: Icons.favorite_border,
                  title: AppStrings.of(context).noMessages,
                  message: AppStrings.of(context).firstMessage,
                );
              }

              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(12),
                itemCount: messages.length,
                itemBuilder: (_, index) {
                  final message = messages[messages.length - 1 - index];
                  final mine = message.senderId == widget.userId;
                  return Align(
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: mine
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (message.content?.isNotEmpty == true)
                            Text(
                              message.content!,
                              style: TextStyle(color: mine ? Colors.white : null),
                            ),
                          if (message.isImage)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.network(message.mediaUrl!, width: 220, height: 220, fit: BoxFit.cover, cacheWidth: 440, filterQuality: FilterQuality.low),
                            ),
                          if (message.isVideo)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: _ChatVideoMessage(url: message.mediaUrl!),
                            ),
                          if (message.isAudio)
                            SizedBox(
                              width: 250,
                              child: _ChatAudioMessage(
                                url: message.mediaUrl!,
                                foregroundColor: mine ? Colors.white : null,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade300))),
          child: Row(
            children: [
              if (_recording) ...[
                Icon(Icons.fiber_manual_record, color: Colors.red.shade600, size: 18),
                const SizedBox(width: 4),
                Text(_voiceTime(_recordingElapsed), style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  tooltip: AppStrings.of(context).t('voice_cancel'),
                  onPressed: _cancelVoiceRecording,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
                IconButton.filled(
                  tooltip: AppStrings.of(context).t('voice_send'),
                  onPressed: _stopAndSendVoice,
                  icon: const Icon(Icons.send_rounded),
                ),
              ] else ...[
                Expanded(
                  child: TextField(
                    controller: msgCtrl,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: AppStrings.of(context).messageHint,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: AppStrings.of(context).t('voice_record'),
                  icon: const Icon(Icons.mic_none_rounded),
                  onPressed: _sending ? null : _startVoiceRecording,
                ),
                IconButton(
                  tooltip: AppStrings.of(context).searchMedia,
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: _sending ? null : _pickMedia,
                ),
                IconButton(
                  icon: _sending
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                  onPressed: _sending ? null : _send,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}



class _ChatPartnerHeader extends StatelessWidget {
  final String partnerId;
  const _ChatPartnerHeader({required this.partnerId});

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    return FutureBuilder<Map<String, dynamic>?>(
      future: client.from('profiles').select('username,avatar_url,status').eq('id', partnerId).maybeSingle(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final name = (data?['username'] ?? AppStrings.of(context).partner).toString();
        final avatar = data?['avatar_url']?.toString();
        return Material(
          color: Theme.of(context).colorScheme.surface,
          child: InkWell(
            onTap: () => context.push('/home/profile/$partnerId'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Row(
                children: [
                  CircleAvatar(radius: 21, backgroundImage: avatar?.isNotEmpty == true ? NetworkImage(avatar!) : null, child: avatar?.isNotEmpty == true ? null : const Icon(Icons.person)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}


class _ChatAudioMessage extends StatefulWidget {
  final String url;
  final Color? foregroundColor;

  const _ChatAudioMessage({required this.url, this.foregroundColor});

  @override
  State<_ChatAudioMessage> createState() => _ChatAudioMessageState();
}

class _ChatAudioMessageState extends State<_ChatAudioMessage> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  PlayerState _state = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _stateSubscription = _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _state = state);
    });
    _durationSubscription = _player.onDurationChanged.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });
    _positionSubscription = _player.onPositionChanged.listen((position) {
      if (mounted) setState(() => _position = position);
    });
  }

  @override
  void didUpdateWidget(covariant _ChatAudioMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      unawaited(_player.stop());
      _duration = Duration.zero;
      _position = Duration.zero;
    }
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      setState(() => _failed = false);
      if (_state == PlayerState.playing) {
        await _player.pause();
      } else if (_state == PlayerState.paused) {
        await _player.resume();
      } else {
        await _player.play(UrlSource(widget.url));
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  String _time(Duration value) =>
      '${value.inMinutes.toString().padLeft(2, '0')}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final color = widget.foregroundColor;
    final maxMs = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: _toggle,
          tooltip: _state == PlayerState.playing ? AppStrings.of(context).pauseAudio : AppStrings.of(context).playAudio,
          icon: Icon(
            _state == PlayerState.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: color,
          ),
        ),
        Expanded(
          child: Slider(
            value: _position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble(),
            max: maxMs,
            onChanged: _duration == Duration.zero
                ? null
                : (value) => _player.seek(Duration(milliseconds: value.round())),
          ),
        ),
        Text(_time(_position), style: TextStyle(color: color, fontSize: 11)),
        if (_failed)
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
      ],
    );
  }
}


class _ChatVideoMessage extends StatefulWidget {
  final String url;
  const _ChatVideoMessage({required this.url});

  @override
  State<_ChatVideoMessage> createState() => _ChatVideoMessageState();
}

class _ChatVideoMessageState extends State<_ChatVideoMessage> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    controller.initialize().then((_) {
      if (mounted) setState(() {});
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox(width: 220, height: 150, child: Center(child: CircularProgressIndicator()));
    }
    return GestureDetector(
      onTap: () => setState(() => controller.value.isPlaying ? controller.pause() : controller.play()),
      child: Stack(alignment: Alignment.center, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(width: 220, height: 150, child: VideoPlayer(controller)),
        ),
        CircleAvatar(
          backgroundColor: Colors.black54,
          child: Icon(controller.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
        ),
      ]),
    );
  }
}

class _ChatQuickActions extends StatelessWidget {
  final VoidCallback onTodo;
  final VoidCallback onInteraction;
  final VoidCallback onCall;

  const _ChatQuickActions({
    required this.onTodo,
    required this.onInteraction,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ActionButton(icon: Icons.check_circle_outline, label: AppStrings.of(context).todo, onTap: onTodo),
            SizedBox(width: 8),

            _ActionButton(icon: Icons.video_call_rounded, label: AppStrings.of(context).call, onTap: onCall),
            SizedBox(width: 8),
            _ActionButton(icon: Icons.favorite_border, label: AppStrings.of(context).send, onTap: onInteraction),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onTap,
    );
  }
}

class _HomeStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _HomeStateView({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class TodoTabScreen extends StatefulWidget {
  final String userId;
  final String partnerId;

  const TodoTabScreen({required this.userId, required this.partnerId, Key? key}) : super(key: key);

  @override
  State<TodoTabScreen> createState() => _TodoTabScreenState();
}

class _TodoTabScreenState extends State<TodoTabScreen> {
  final todoCtrl = TextEditingController();
  bool _adding = false;
  late final Stream<List<TodoItem>> _todosStream;

  @override
  void dispose() {
    todoCtrl.dispose();
    super.dispose();
  }

  Future<void> _addTodo() async {
    final title = todoCtrl.text.trim();
    if (title.isEmpty || _adding) return;

    setState(() => _adding = true);
    try {
      await context.read<TodoService>().addTodo(widget.userId, widget.partnerId, title);
      todoCtrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.of(context).error}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _todosStream = context.read<TodoService>().getTodosStream(widget.userId, widget.partnerId);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<TodoItem>>(
            stream: _todosStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _HomeStateView(
                  icon: Icons.cloud_off_outlined,
                  title: AppStrings.of(context).errorLoading + ' ' + AppStrings.of(context).tasks,
                  message: AppStrings.of(context).checkConnection,
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final todos = snapshot.data!;
              if (todos.isEmpty) {
                return _HomeStateView(
                  icon: Icons.check_circle_outline,
                  title: AppStrings.of(context).noTasks,
                  message: AppStrings.of(context).newTask,
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: todos.length,
                itemBuilder: (_, i) {
                  final todo = todos[i];
                  return ListTile(
                    leading: Checkbox(
                      value: todo.isCompleted,
                      onChanged: (value) async {
                        if (value == null) return;
                        try {
                          await context.read<TodoService>().toggleTodo(todo.id, todo.isCompleted);
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('${AppStrings.of(context).error}: $e')),
                            );
                          }
                        }
                      },
                    ),
                    title: Text(
                      todo.title,
                      style: TextStyle(
                        decoration: todo.isCompleted ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () async {
                        try {
                          await context.read<TodoService>().deleteTodo(todo.id);
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('${AppStrings.of(context).error}: $e')),
                            );
                          }
                        }
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade300))),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: todoCtrl,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addTodo(),
                  decoration: InputDecoration(
                    hintText: AppStrings.of(context).newTask,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: _adding
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add),
                onPressed: _adding ? null : _addTodo,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class GamesTabScreen extends StatelessWidget {
  const GamesTabScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.all(16),
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: 0.95,
      children: [
        GameCard(title: AppStrings.of(context).gameMostLikely, emoji: '🎯', onTap: () => context.go('/home/game-lobby/most_likely_to')),
        GameCard(title: AppStrings.of(context).gameTrivia, emoji: '🧠', onTap: () => context.go('/home/game-lobby/trivia')),
        GameCard(title: AppStrings.of(context).gameWord, emoji: '🔤', onTap: () => context.go('/home/game-lobby/word_game')),
        GameCard(title: AppStrings.of(context).gameNameCityAnimal, emoji: '🎯', onTap: () => context.go('/home/game-lobby/name_city_animal')),
      ],
    );
  }
}

class GameCard extends StatelessWidget {
  final String title, emoji;
  final VoidCallback onTap;

  const GameCard({required this.title, required this.emoji, required this.onTap, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(24),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58, height: 58,
                decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(18)),
                alignment: Alignment.center,
                child: Text(emoji, style: const TextStyle(fontSize: 30)),
              ),
              Spacer(),
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              SizedBox(height: 8),
              Row(children: [Expanded(child: Text(AppStrings.of(context).open, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700))), Icon(Icons.arrow_forward_rounded, color: scheme.primary)]),
            ],
          ),
        ),
      ),
    );
  }
}

class RelationshipHubScreen extends StatelessWidget {
  RelationshipHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final cards = [
      (Icons.timer_rounded, s.countdown, s.countdownSubtitle, '/home/countdown'),
      (Icons.mood_rounded, s.mood, s.moodSubtitle, '/home/mood'),
      (Icons.mail_rounded, s.loveLetters, s.loveLettersSubtitle, '/home/love-letters'),
      (Icons.map_rounded, s.map, s.mapSubtitle, '/home/map'),
      (Icons.forum_rounded, s.conversationFinder, s.conversationFinderSubtitle, '/home/conversation-topics'),
      (Icons.photo_library_rounded, s.hallOfFame, s.hallOfFameSubtitle, '/home/hall-of-fame'),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [scheme.primary, scheme.primaryContainer]),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.relationshipHub, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(s.relationshipHubSubtitle, style: TextStyle(color: Colors.white.withOpacity(.9), height: 1.35)),
            const SizedBox(height: 14),
            Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7), decoration: BoxDecoration(color: Colors.white.withOpacity(.16), borderRadius: BorderRadius.circular(99)), child: Text(s.togetherTag, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          ]),
        ),
        const SizedBox(height: 18),
        ...cards.map((card) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(22),
            elevation: 1,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => context.push(card.$4),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(children: [
                  Container(width: 54, height: 54, decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(17)), child: Icon(card.$1, color: scheme.onSecondaryContainer)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(card.$2, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(card.$3, style: Theme.of(context).textTheme.bodyMedium)])),
                  Icon(Icons.chevron_right_rounded, color: scheme.primary),
                ]),
              ),
            ),
          ),
        )),
      ],
    );
  }
}
