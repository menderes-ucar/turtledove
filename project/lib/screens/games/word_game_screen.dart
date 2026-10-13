import 'package:flutter/material.dart';
import 'word_game_localization.dart';

class WordGameScreen extends StatefulWidget {
  const WordGameScreen({Key? key}) : super(key: key);

  @override
  State<WordGameScreen> createState() => _WordGameScreenState();
}

class _WordGameScreenState extends State<WordGameScreen> {
  final wordCtrl = TextEditingController();

  @override
  void dispose() {
    wordCtrl.dispose();
    super.dispose();
  }
  List<String> words = [];
  int wrongCount = 0;
  static const int maxWrong = 3;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(WordGameStrings.of(context).title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${WordGameStrings.of(context).score}: ${words.length}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: wrongCount >= maxWrong ? Colors.red : Colors.orange,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${WordGameStrings.of(context).mistakes}: $wrongCount/$maxWrong',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          if (wrongCount >= maxWrong)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.red.shade100,
              child: Column(
                children: [
                  Text(WordGameStrings.of(context).gameOver, style: TextStyle(color: Colors.red.shade900, fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text('${WordGameStrings.of(context).finalScore}: ${words.length}', style: TextStyle(color: Colors.red.shade900, fontSize: 18)),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        words.clear();
                        wrongCount = 0;
                        wordCtrl.clear();
                      });
                    },
                    child: Text(WordGameStrings.of(context).restart),
                  ),
                ],
              ),
            )
          else
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (words.isNotEmpty) ...[
                    Text(WordGameStrings.of(context).lastWord, style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        words.last,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${WordGameStrings.of(context).nextLetterHint} ${String.fromCharCode(words.last.runes.last).toUpperCase()}',
                      textAlign: TextAlign.center,
                    ),
                  ] else
                    Text(WordGameStrings.of(context).startHint, style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),
          if (words.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey.shade100,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(WordGameStrings.of(context).words, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: words
                        .map((w) => Chip(label: Text(w)))
                        .toList(),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade300))),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: wordCtrl,
                    decoration: InputDecoration(
                      hintText: WordGameStrings.of(context).enterWord,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => _addWord(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _addWord,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addWord() {
    final word = wordCtrl.text.trim().toLowerCase();
    wordCtrl.clear();

    if (word.isEmpty) return;

    if (words.isNotEmpty) {
      final lastLetter = String.fromCharCode(words.last.runes.last).toLowerCase();
      if (!word.startsWith(lastLetter)) {
        setState(() => wrongCount++);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${WordGameStrings.of(context).mustStartWith} "$lastLetter" ❌')),
        );
        return;
      }

      if (words.contains(word)) {
        setState(() => wrongCount++);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(WordGameStrings.of(context).alreadyUsed)),
        );
        return;
      }
    }

    setState(() => words.add(word));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"$word" ${WordGameStrings.of(context).added} ✅')),
    );
  }
}
