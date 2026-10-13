import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../localization/app_strings.dart';

class PartnerProfileScreen extends StatelessWidget {
  final String profileId;
  final String userId;

  const PartnerProfileScreen({
    super.key,
    required this.profileId,
    required this.userId,
  });

  Future<Map<String, dynamic>?> _loadProfile() {
    return Supabase.instance.client
        .from('profiles')
        .select('id,username,avatar_url,status,paired_with')
        .eq('id', profileId)
        .maybeSingle();
  }

  Future<List<String>> _loadMedia() async {
    final client = Supabase.instance.client;
    final rows = await client
        .from('messages')
        .select('sender_id,receiver_id,media_url,created_at')
        .or('and(sender_id.eq.$userId,receiver_id.eq.$profileId),and(sender_id.eq.$profileId,receiver_id.eq.$userId)')
        .not('media_url', 'is', null)
        .order('created_at', ascending: false);

    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .where((row) {
          final sender = row['sender_id']?.toString();
          final receiver = row['receiver_id']?.toString();
          return ((sender == userId && receiver == profileId) ||
                  (sender == profileId && receiver == userId)) &&
              (row['media_url']?.toString().isNotEmpty ?? false);
        })
        .map((row) => row['media_url'].toString())
        .where((url) {
          final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
          return !RegExp(r'\.(m4a|mp3|aac|wav|ogg|opus|caf|3gp|amr|mp4|mov|m4v|webm|avi)$')
              .hasMatch(path);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).partnerProfile)),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _loadProfile(),
        builder: (context, profileSnapshot) {
          if (profileSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final profile = profileSnapshot.data;
          if (profile == null) {
            return Center(child: Text('${AppStrings.of(context).errorLoading}: ${AppStrings.of(context).profile}'));
          }

          final username = profile['username']?.toString() ?? AppStrings.of(context).partner;
          final avatar = profile['avatar_url']?.toString();
          final status = profile['status']?.toString() ?? 'offline';

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 58,
                      backgroundImage: avatar == null || avatar.isEmpty ? null : NetworkImage(avatar),
                      child: avatar == null || avatar.isEmpty ? const Icon(Icons.person, size: 58) : null,
                    ),
                    SizedBox(height: 14),
                    Text(username, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                    SizedBox(height: 5),
                    Text(_statusText(status, AppStrings.of(context)), style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => context.push('/home/profile/$profileId/voice-messages'),
                icon: const Icon(Icons.mic_rounded),
                label: Text(AppStrings.of(context).t('voice_archive_open')),
              ),
              SizedBox(height: 26),
              Text(AppStrings.of(context).sharedMedia, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              FutureBuilder<List<String>>(
                future: _loadMedia(),
                builder: (context, mediaSnapshot) {
                  if (mediaSnapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final urls = mediaSnapshot.data ?? const <String>[];
                  if (urls.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text(AppStrings.of(context).noSharedMediaYet)),
                    );
                  }
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: urls.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 7,
                      mainAxisSpacing: 7,
                    ),
                    itemBuilder: (_, index) => ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        urls[index],
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => ColoredBox(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  String _statusText(String value, AppStrings strings) {
    switch (value) {
      case 'online':
        return strings.online;
      case 'away':
        return strings.away;
      default:
        return strings.offline;
    }
  }
}
