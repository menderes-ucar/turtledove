import 'package:flutter/material.dart';
import '../../localization/app_strings.dart';
import 'package:provider/provider.dart';

import '../../models/interaction_model.dart';
import '../../services/interaction_service.dart';

class InteractionHistoryScreen extends StatefulWidget {
  final String userId;

  const InteractionHistoryScreen({required this.userId, Key? key}) : super(key: key);

  @override
  State<InteractionHistoryScreen> createState() => _InteractionHistoryScreenState();
}

class _InteractionHistoryScreenState extends State<InteractionHistoryScreen> {
  late final Stream<List<Interaction>> _interactionsStream;

  @override
  void initState() {
    super.initState();
    _interactionsStream = context.read<InteractionService>().getInteractionsStream(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).interactionHistory)),
      body: StreamBuilder<List<Interaction>>(
        stream: _interactionsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('${AppStrings.of(context).interactionLoadFailed}: ${snapshot.error}'),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snapshot.data!;
          if (items.isEmpty) {
            return Center(child: Text(AppStrings.of(context).noInteractions));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, index) {
              final interaction = items[index];
              return Card(
                child: ListTile(
                  leading: Text(
                    interaction.getEmoji(),
                    style: const TextStyle(fontSize: 30),
                  ),
                  title: Text(
                    interaction.getMessage('Partnerin'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(_formatDate(interaction.createdAt)),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day.$month.${local.year} • $hour:$minute';
  }
}
