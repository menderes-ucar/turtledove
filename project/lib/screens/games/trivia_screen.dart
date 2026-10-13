import 'dart:async';

import 'package:flutter/material.dart';
import '../../localization/app_strings.dart';

class TriviaScreen extends StatefulWidget {
  const TriviaScreen({Key? key}) : super(key: key);

  @override
  State<TriviaScreen> createState() => _TriviaScreenState();
}

class _TriviaScreenState extends State<TriviaScreen> {
  static const questions = [
    ('Dünya\'nın en yüksek dağı neresidir?', ['Everest', 'K2', 'Kangchenjunga', 'Lhotse'], 0),
    ('Kaç tane kıta vardır?', ['5', '6', '7', '8'], 2),
    ('Güneşin çapı Dünya\'nın kaç katıdır?', ['100', '200', '300', '109'], 3),
    ('En derin okyanus çukuru hangisidir?', ['Mariana', 'Tonga', 'Kuril', 'Kamçatka'], 0),
    ('İnsan vücudunda kaç kemik vardır?', ['186', '206', '226', '246'], 1),
  ];

  int _questionIndex = 0;
  int _score = 0;
  Duration _timeLeft = const Duration(seconds: 15);
  Timer? _timer;
  bool _answering = false;
  bool _gameFinished = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _timeLeft = const Duration(seconds: 15));

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _gameFinished) {
        timer.cancel();
        return;
      }

      if (_timeLeft.inSeconds <= 1) {
        timer.cancel();
        _nextQuestion(null);
      } else {
        setState(() {
          _timeLeft = Duration(seconds: _timeLeft.inSeconds - 1);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final (question, answers, correct) = questions[_questionIndex];

    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).gameTrivia)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${AppStrings.of(context).t('score')}: $_score', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _timeLeft.inSeconds <= 5 ? Colors.red : Colors.green,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_timeLeft.inSeconds}s',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          LinearProgressIndicator(value: (_questionIndex + 1) / questions.length),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${AppStrings.of(context).t('question')} ${_questionIndex + 1}/${questions.length}', style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 30),
                  Text(question, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 50),
                  ...List.generate(
                    answers.length,
                    (i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _answering ? null : () => _nextQuestion(i),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade200,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(answers[i]),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _nextQuestion(int? answer) {
    if (_answering || _gameFinished) return;

    _answering = true;
    _timer?.cancel();

    if (answer == questions[_questionIndex].$3) {
      _score++;
    }

    if (_questionIndex < questions.length - 1) {
      setState(() {
        _questionIndex++;
        _timeLeft = const Duration(seconds: 15);
        _answering = false;
      });
      _startTimer();
    } else {
      setState(() => _gameFinished = true);
      _showFinalScore();
    }
  }

  void _showFinalScore() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.of(context).t('game_over')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Final Puan: $_score/${questions.length}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text('${AppStrings.of(context).t('success')}: ${((_score / questions.length) * 100).toStringAsFixed(0)}%'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: Text(AppStrings.of(context).t('done')),
          ),
        ],
      ),
    );
  }
}
