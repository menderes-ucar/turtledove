import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/question.dart';
import '../providers/quiz_provider.dart';

class QuizScreen extends StatelessWidget {
  const QuizScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<QuizProvider>();
    final question = provider.currentQuestion;

    if (provider.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (question == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Quiz'),
        ),
        body: Center(
          child: Text(
            provider.errorMessage ??
                'Aktif bir quiz bulunmuyor. Önce bir quiz başlatın.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final selectedOption = provider.currentAnswerOption;
    final answered = selectedOption != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Soru ${provider.currentQuestionIndex + 1}/${provider.questions.length}',
        ),
        actions: [
          if (provider.currentQuizAttempt?.isTimed == true)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Text(
                  provider.formattedTime,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            question.questionText,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 20),
          ..._buildOptions(
            context,
            question,
            selectedOption,
            answered,
          ),
          if (answered) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.isCurrentAnswerCorrect == true
                          ? 'Doğru'
                          : 'Yanlış',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Doğru cevap: ${provider.currentCorrectOption ?? '-'}',
                    ),
                    if (provider.currentExplanation != null &&
                        provider.currentExplanation!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(provider.currentExplanation!),
                    ],
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: provider.hasPreviousQuestion
                      ? provider.previousQuestion
                      : null,
                  child: const Text('Önceki'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: provider.hasNextQuestion
                      ? provider.nextQuestion
                      : provider.completeQuiz,
                  child: Text(
                    provider.hasNextQuestion ? 'Sonraki' : 'Bitir',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildOptions(
    BuildContext context,
    Question question,
    String? selectedOption,
    bool answered,
  ) {
    final options = <String, String>{
      'A': question.optionA,
      'B': question.optionB,
      'C': question.optionC,
      'D': question.optionD,
      if (question.optionE?.isNotEmpty == true)
        'E': question.optionE!,
    };

    return options.entries.map((entry) {
      final isSelected = selectedOption == entry.key;

      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: OutlinedButton(
          onPressed: answered
              ? null
              : () => context.read<QuizProvider>().selectAnswer(entry.key),
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.all(16),
          ),
          child: Row(
            children: [
              Text(
                '${entry.key}. ',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Expanded(child: Text(entry.value)),
              if (isSelected) const Icon(Icons.check_circle_outline),
            ],
          ),
        ),
      );
    }).toList();
  }
}
