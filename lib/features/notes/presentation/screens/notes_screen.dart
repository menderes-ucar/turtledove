import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/note.dart';
import '../providers/notes_provider.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotesProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotesProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notlar'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),
      body: provider.loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : provider.error != null
              ? Center(
                  child: Text(provider.error!),
                )
              : provider.notes.isEmpty
                  ? const Center(
                      child: Text('Henüz not eklenmedi.'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: provider.notes.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        final note = provider.notes[index];

                        return Card(
                          child: ListTile(
                            title: Text(note.title),
                            subtitle: Text(
                              note.content,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _openEditor(note: note),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(note),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }

  Future<void> _openEditor({Note? note}) async {
    final titleController = TextEditingController(text: note?.title ?? '');
    final contentController = TextEditingController(
      text: note?.content ?? '',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(note == null ? 'Yeni Not' : 'Notu Düzenle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Başlık',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Not',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () async {
                final title = titleController.text.trim();
                final content = contentController.text.trim();

                if (title.isEmpty || content.isEmpty) {
                  return;
                }

                try {
                  await context.read<NotesProvider>().save(
                        id: note?.id,
                        title: title,
                        content: content,
                      );

                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop(true);
                  }
                } catch (_) {
                  // Provider keeps the error state.
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );

    titleController.dispose();
    contentController.dispose();

    if (saved == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _delete(Note note) async {
    await context.read<NotesProvider>().delete(note.id);
  }
}
