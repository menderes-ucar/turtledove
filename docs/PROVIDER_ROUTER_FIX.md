# Provider / Router Runtime Fix

## Problem

`HomeScreen` could be opened before `AuthProvider` existed because `KpssKolayApp`
returned `MaterialApp.router` directly when the Supabase client was null.
The router also always started at `/` without an authentication redirect.

This produced:

```text
ProviderNotFoundException
Could not find the correct Provider<AuthProvider> above this HomeScreen widget
```

## Fix

- `MultiProvider` is now the composition root whenever Supabase is configured.
- `HomeScreen` and all authenticated routes are descendants of `AuthProvider`.
- `GoRouter` listens to `AuthProvider` via `refreshListenable`.
- Unauthenticated users are redirected to `/login`.
- Authenticated users visiting `/login` are redirected to `/`.
- Login no longer calls `Navigator.pop()`. Router state performs the transition.
- Missing Supabase configuration now displays a configuration screen instead of
  rendering provider-dependent application screens.
- `QuizProvider` remains a `ChangeNotifierProxyProvider<AuthProvider, QuizProvider>`
  and receives the current user id when auth state changes.

## Dependency fix included

For Dart 3.8.1, this package uses:

```yaml
supabase_flutter: ^2.15.4
sign_in_with_apple: ^7.0.1
```

This prevents the old `sign_in_with_apple 5.0.0` Flutter v1 embedding code from
being selected when the dependency solver permits the declared version.

## Verification

On a machine with Flutter installed:

```powershell
flutter clean
Remove-Item -Recurse -Force .dart_tool -ErrorAction SilentlyContinue
Remove-Item -Force pubspec.lock -ErrorAction SilentlyContinue
flutter pub get
flutter pub deps --style=compact | Select-String "supabase_flutter|sign_in_with_apple"
flutter analyze
flutter run --dart-define=SUPABASE_URL=YOUR_URL --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

The dependency output must not contain `sign_in_with_apple 5.0.0`.
