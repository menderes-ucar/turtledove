import 'package:flutter/material.dart';

class MostLikelyToScreen extends StatefulWidget {
  const MostLikelyToScreen({Key? key}) : super(key: key);

  @override
  State<MostLikelyToScreen> createState() => _MostLikelyToScreenState();
}

class _MostLikelyToScreenState extends State<MostLikelyToScreen> {
  static const questions = [
    'Daha çok atılgan kişi kim?',
    'Daha çok mizah anlayan kim?',
    'Daha çok ruhsal desteği olan kim?',
    'Daha iyi dinleyici kim?',
    'Daha çok iyimser kim?',
  ];

  int _questionIndex = 0;
  final _answers = <int>[];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('En Çok Kim?')),
      body: Column(
        children: [
          LinearProgressIndicator(value: (_questionIndex + 1) / questions.length),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Soru ${_questionIndex + 1}/${questions.length}', style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 20),
                  Text(
                    questions[_questionIndex],
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 60),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        icon: const Text('👤', style: TextStyle(fontSize: 30)),
                        label: const Text('Ben'),
                        onPressed: () => _nextQuestion(0),
                      ),
                      ElevatedButton.icon(
                        icon: const Text('👥', style: TextStyle(fontSize: 30)),
                        label: const Text('Partnerin'),
                        onPressed: () => _nextQuestion(1),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _nextQuestion(int answer) {
    _answers.add(answer);
    if (_questionIndex < questions.length - 1) {
      setState(() => _questionIndex++);
    } else {
      _showResults();
    }
  }

  void _showResults() {
    final benScore = _answers.where((a) => a == 0).length;
    final partnerScore = _answers.where((a) => a == 1).length;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sonuçlar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Ben: $benScore puan', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text('Partnerin: $partnerScore puan', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }
}
