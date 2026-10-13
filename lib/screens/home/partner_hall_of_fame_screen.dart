import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

import '../../localization/app_strings.dart';
import '../../models/hall_of_fame_photo_model.dart';
import '../../services/hall_of_fame_service.dart';

class PartnerHallOfFameScreen extends StatefulWidget {
  const PartnerHallOfFameScreen({super.key});

  @override
  State<PartnerHallOfFameScreen> createState() => _PartnerHallOfFameScreenState();
}

class _PartnerHallOfFameScreenState extends State<PartnerHallOfFameScreen> {
  late final HallOfFameService service;
  late final String userId;
  String category = 'aura';
  String? partnerId;

  @override
  void initState() {
    super.initState();
    final client = Supabase.instance.client;
    service = HallOfFameService(client);
    userId = client.auth.currentUser?.id ?? '';
    partnerId = context.read<AuthProvider>().profile?.pairedWith;
  }

  String _categoryTitle(AppStrings s, String value) => switch (value) {
        'meme' => s.hallOfFameMeme,
        'mood' => s.hallOfFameMood,
        _ => s.hallOfFameAura,
      };

  Future<void> _pick() async {
    final s = AppStrings.of(context);
    try {
      await service.addFromGallery(userId: userId, category: category);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.hallOfFameSaved)));
      }
    } on StateError catch (e) {
      if (e.message == 'HALL_OF_FAME_LIMIT' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.hallOfFameLimit)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.hallOfFameUploadFailed)));
      }
    }
  }

  Future<void> _editNote(HallOfFamePhoto photo) async {
    final s = AppStrings.of(context);
    final controller = TextEditingController(text: photo.note ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.hallOfFamePhotoNote),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: InputDecoration(hintText: s.hallOfFameAddNote),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(s.save)),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    try {
      await service.updateNote(photoId: photo.id, note: value);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.hallOfFameUploadFailed)));
    }
  }

  Future<void> _delete(HallOfFamePhoto photo) async {
    final s = AppStrings.of(context);
    try {
      await service.deletePhoto(photo);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.hallOfFameDeleteFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.hallOfFame),
        actions: [IconButton(onPressed: _pick, tooltip: s.hallOfFameAdd, icon: const Icon(Icons.add_a_photo_rounded))],
      ),
      body: StreamBuilder<List<HallOfFamePhoto>>(
        stream: partnerId == null || partnerId!.isEmpty
            ? const Stream<List<HallOfFamePhoto>>.empty()
            : service.streamPhotos(userId, partnerId!),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text(s.hallOfFameUploadFailed));
          final all = snapshot.data ?? const <HallOfFamePhoto>[];
          final visible = all.where((p) => p.category == category).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'aura', label: Text(s.hallOfFameAura), icon: const Icon(Icons.auto_awesome_rounded)),
                    ButtonSegment(value: 'meme', label: Text(s.hallOfFameMeme), icon: const Icon(Icons.sentiment_very_satisfied_rounded)),
                    ButtonSegment(value: 'mood', label: Text(s.hallOfFameMood), icon: const Icon(Icons.favorite_rounded)),
                  ],
                  selected: {category},
                  onSelectionChanged: (v) => setState(() => category = v.first),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                child: Row(children: [Expanded(child: Text(_categoryTitle(s, category), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))), Text('${all.length}/10', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800))]),
              ),
              Expanded(
                child: visible.isEmpty
                    ? Center(child: Padding(padding: const EdgeInsets.all(30), child: Text(s.hallOfFameEmpty, textAlign: TextAlign.center)))
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .82),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final photo = visible[index];
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(photo.publicUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: scheme.surfaceContainerHighest, child: const Icon(Icons.broken_image_outlined))),
                                Positioned(top: 7, right: 7, child: PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
                                  color: scheme.surface,
                                  onSelected: (value) => value == 'note' ? _editNote(photo) : _delete(photo),
                                  itemBuilder: (_) => [PopupMenuItem(value: 'note', child: Text(s.hallOfFameAddNote)), PopupMenuItem(value: 'delete', child: Text(s.hallOfFameDelete))],
                                )),
                                if ((photo.note ?? '').isNotEmpty)
                                  Positioned(left: 8, right: 8, bottom: 8, child: Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: Colors.black.withOpacity(.58), borderRadius: BorderRadius.circular(13)), child: Text(photo.note!, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)))),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _pick, icon: const Icon(Icons.add_rounded), label: Text(s.hallOfFameAdd)),
    );
  }
}
