# KPSS Kolay — Phase 1 Quiz Integration

## Implemented in this package

- `26_quiz_core_hardening_v2.sql`: patches the Phase 0 migration.
- `27_quiz_provider.dart`: server-authoritative Provider.
- `28_question_model_patch.md`: exact model change needed to prevent answer-key assumptions.

## New data flow

1. `start_quiz_session()` selects questions server-side.
2. `get_quiz_questions()` returns only public question fields for that session.
3. Client displays questions without `correct_option`.
4. `submit_quiz_answer()` calculates correctness server-side.
5. Server returns correctness + answer key + explanation only after submission.
6. Wrong answers are written to `error_notebook` in the same server transaction.
7. `complete_quiz_session()` calculates correct/wrong/blank/net server-side and creates `user_quiz_attempts` atomically.

## Remaining integration work

- Replace the old `QuizProvider` in `09_main.dart` with the Provider in `27_quiz_provider.dart`.
- Update `05_quiz_screen.dart` so feedback waits for `selectAnswer()` and uses `currentCorrectOption/currentExplanation`.
- Apply the nullable `correctOption` model patch.
- Do not expose `questions.correct_option` or `questions.explanation` through a normal client SELECT.
- Run `flutter analyze`, unit tests, and a real Supabase integration test suite before release.

No claim of release readiness is made until those gates pass.
