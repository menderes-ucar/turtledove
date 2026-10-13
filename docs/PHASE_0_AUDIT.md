# KPSS Kolay — Phase 0 Audit & Rebuild Bundle

Date: 2026-09-18

## What is in this bundle

This ZIP preserves the supplied source artifacts and adds a first canonical backend hardening migration. The original files are **not silently overwritten**.

## Verified problems from the supplied files

1. `01_supabase_schema.sql` has a schema mismatch with the later error-notebook implementation: the base table uses `resolved` / `note_text`, while later Dart/SQL expects `is_resolved` / `user_note`.
2. The base `questions` table contains `correct_option` and has a broad authenticated-readable policy. That means a client can potentially request the answer key directly.
3. The original `03_provider_state_layer.dart` performs client-side question loading and constructs quiz attempts locally. This is not sufficient for a secure quiz session.
4. `06_error_notebook_screen.dart` still contains a TODO for marking an error resolved.
5. The later `24_error_notebook_real.dart` still accepts `userId` and `correctOption` as client-side inputs to its RPC contract. The server should derive both from the authenticated session/question data.
6. The later quiz security documents correctly identify session ownership, duplicate-answer, option validation and server-timer checks, but those documents are implementation material rather than proof that the migration is deployed.
7. `24c_pubspec_cleaned.yaml` is still a documentation/explanation file rather than a verified project `pubspec.yaml`; it also retains monetization packages even though monetization is currently out of scope.
8. `09_main.dart` contains provider wiring that references a mixed old/new repository/provider design and still includes premium wiring.
9. The supplied platform configuration contains legacy storage permissions and Firebase Dynamic Links configuration that should not be copied blindly into the real Android/iOS project.

## Canonical decisions for the rebuild

- State: Provider only.
- Backend: Supabase/PostgreSQL.
- Quiz correctness: server-side only.
- Quiz ownership: `auth.uid()` only; never trust a client-supplied user id.
- Quiz question membership: server-created session question IDs.
- Answer options: only A/B/C/D/E.
- Duplicate answer: database uniqueness constraint + server validation.
- Timer: server timestamp validation; client countdown is UI only.
- Public question data: a restricted view without `correct_option`.
- Error notebook: populated by the answer RPC, not by client-supplied correctness data.
- Monetization: intentionally excluded from this phase.

## Important limitation

This is a **Phase 0/1 source bundle**, not a claim that the app is already store-ready. The real Flutter project still needs the canonical files wired into its actual directory tree, followed by `flutter analyze`, unit/widget/integration tests, Android release build, iOS archive/TestFlight build, and a live Supabase migration test.
