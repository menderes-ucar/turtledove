import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/subjects_provider.dart';

class SubjectsScreen extends StatefulWidget {
  const SubjectsScreen({super.key});

  @override
  State<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends State<SubjectsScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SubjectsProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SubjectsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dersler'),
      ),
      body: provider.loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : provider.error != null
              ? Center(
                  child: Text(provider.error!),
                )
              : provider.subjects.isEmpty
                  ? const Center(
                      child: Text('Henüz ders bulunamadı.'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: provider.subjects.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        final subject = provider.subjects[index];

                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.menu_book),
                            ),
                            title: Text(subject.name),
                            subtitle: Text(
                              subject.description ??
                                  'KPSS konu ve soru çalışmaları',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                          ),
                        );
                      },
                    ),
    );
  }
}
