# Legacy Source Policy

The files previously stored under `legacy_source/` are historical drafts and security experiments from earlier iterations of KPSS Kolay.

They are **not application source code** and must not be imported, compiled, or analyzed as part of the Flutter package. Several of those files intentionally contain mutually incompatible versions of the same classes, plus Android/Kotlin/XML snippets stored in a Dart file. Treating them as active Dart source causes misleading compiler/analyzer errors.

For traceability, the original contents are preserved under:

`docs/legacy_source_archive/`

Dart files have the `.dart.txt` suffix so the analyzer and IDE cannot treat them as package source files.

The active implementation is only under `lib/` (plus `test/` and `integration_test/`).
