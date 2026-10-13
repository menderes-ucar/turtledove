import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/error_notebook_provider.dart';

class ErrorNotebookScreen extends StatefulWidget {
  const ErrorNotebookScreen({super.key});

  @override
  State<ErrorNotebookScreen> createState() => _ErrorNotebookScreenState();
}

class _ErrorNotebookScreenState extends State<ErrorNotebookScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ErrorNotebookProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ErrorNotebookProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Yanlış Defteri'),
        actions: [
          Switch(
            value: provider.showResolved,
            onChanged: provider.setShowResolved,
          ),
        ],
      ),
      body: provider.loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : provider.error != null
              ? Center(
                  child: Text(provider.error!),
                )
              : provider.items.isEmpty
                  ? const Center(
                      child: Text('Yanlış defterinde kayıt bulunamadı.'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: provider.items.length,
                      itemBuilder: (_, index) {
                        final item = provider.items[index];

                        return Card(
                          child: ListTile(
                            title: Text('Soru: ${item.questionId}'),
                            subtitle: Text(
                              '${item.wrongCount} kez yanlış • '
                              '${item.resolved ? 'Çözüldü' : 'Tekrar et'}',
                            ),
                            trailing: IconButton(
                              icon: Icon(
                                item.resolved
                                    ? Icons.refresh
                                    : Icons.check,
                              ),
                              onPressed: () {
                                if (item.resolved) {
                                  provider.reopen(item.id);
                                } else {
                                  provider.resolve(item.id);
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
