# Phase 2 Compile Fixes

Date: 2026-09-19

This revision fixes the concrete Dart errors found in the Phase 2 architecture snapshot.

## Fixed

- `main.dart`
  - Replaced `const AppConfig.fromEnvironment()` with `final config = AppConfig.fromEnvironment()` because the factory constructor is not const.
- `app/providers/app_providers.dart`
  - Added the explicit `provider/single_child_widget.dart` import.
  - Fixed `QuizProvider` named arguments to `completeQuizUseCase` and `abandonQuizUseCase`.
  - Switched quiz provider composition to `ChangeNotifierProxyProvider<AuthProvider, QuizProvider>` so the authenticated user ID follows auth state.
- `quiz_provider.dart`
  - Made the user ID updateable through `setUserId`.
  - Added authenticated-user validation before starting a quiz.
  - Kept server-authoritative answer/score handling.
- `error_notebook_remote_datasource.dart`
  - Fixed Supabase query builder typing by applying `.eq()` before `.order()`.
- Formatting
  - Reworked the feature screens and affected data/provider files into readable multi-line Dart instead of compressed one-line source.
- `pubspec.yaml`
  - Uses `flutter_tts: ^4.2.5` for Dart 3.8.1 null-safety compatibility.

## Verification limitation

The build environment used to prepare this archive does not contain the Flutter/Dart SDK and cannot access the public package registry, so `flutter pub get`, `flutter analyze`, `flutter test`, and platform builds were not executable here.

After extracting the project locally, run:

```bash
flutter clean
flutter pub get
flutter analyze
flutter test
```

The next errors, if any, should be handled from the actual analyzer output rather than guessed.
