# QuestionModel security patch

The quiz question model must not require `correct_option` from the database question payload.

Change `QuestionModel` so `correctOption` is nullable and `fromJson()` reads it only when a trusted post-answer payload supplies it:

```dart
final String? correctOption;

correctOption: (json['correct_option'] as String?)?.toUpperCase(),
```

Do not serialize `correct_option` from client question creation/update flows.

The quiz UI should use `QuizProvider.currentCorrectOption` and
`QuizProvider.currentExplanation` after `submit_quiz_answer` instead of reading
`question.correctOption` or `question.explanation` from the question payload.
