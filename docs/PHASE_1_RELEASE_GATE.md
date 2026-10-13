# Phase 1 — Quiz Release Gate

## Source changes in this package

1. `26_quiz_core_hardening_v2.sql`
   - Adds session-scoped question retrieval without answer keys.
   - Keeps explanations server-side until an answer is submitted.
   - Adds error-notebook quiz start.
   - Makes duplicate answers explicit.
   - Allows timed quizzes to complete after expiry and caps duration.
   - Adds server-side abandon RPC.

2. `27_quiz_provider.dart`
   - Replaces client-side question loading and scoring.
   - Uses Supabase RPCs for start, answer, completion and abandonment.
   - Stores answer key/explanation only after the server returns them.

3. `02_dart_models.dart`
   - `QuestionModel.correctOption` is nullable and no longer defaults to `A`.

4. `05_quiz_screen.dart`
   - Waits for server answer submission before showing correctness.
   - Uses provider-owned answer key/explanation.

## Verification still required

- Run the V2 SQL against a disposable Supabase project.
- Verify RLS and RPC permissions with an authenticated user and a second user.
- Verify a user cannot read `questions.correct_option` with the anon/authenticated client.
- Verify a user cannot submit a question outside their session.
- Verify duplicate answer attempts fail.
- Verify an expired timed quiz completes with remaining questions as blank.
- Verify wrong answers create/update exactly one error-notebook row.
- Run `flutter analyze` and `flutter test` in the real Flutter project.
- Run Android release build and iOS release/archive build.

Until these checks pass on the actual project, the app should not be labeled publish-ready.
