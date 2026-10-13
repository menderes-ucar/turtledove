# Bestie Release Audit — 2026-10-06

## What was found

### Games
- Most Likely To had a real production game-round architecture in the project, but the standalone `MostLikelyToScreen` was a 5-question hard-coded demo. It is now routed to the production lobby/round architecture.
- Trivia had the same problem: the standalone screen contained only 5 hard-coded Turkish questions. It is now routed to the production lobby/round architecture.
- Most Likely To now uses the two real player identities as the answer choices (`You` / `Partner`) instead of a free-text field.
- Name-City-Animal was added as a separate server-authoritative multiplayer game.

### Content
- Most Likely To: 5,000 records, 5 languages, 5,000 unique prompts per language.
- Spanish Most Likely To had a repeated grammar defect (`es más probable que + infinitive`); the production content was normalized to the grammatical `tiene más probabilidades de + infinitive` construction.
- French Most Likely To had vowel-elision defects such as `de entrer`; these were normalized to `d’entrer`-style forms.
- Trivia source data contained 5,000 IDs but only 2,310 distinct underlying Turkish prompts after generated round/quiz prefixes were removed. The release seed therefore uses the 2,310 distinct questions rather than padding the database with duplicates.
- All 2,310 retained Trivia questions have localized prompts in TR/EN/DE/ES/FR and the localized correct answer remains present in the source content, while the public question RPC explicitly withholds the answer key from clients.
- Trivia options are mostly proper nouns/numbers and remain shared where the name is conventionally shared; the recurring Turkish-language option phrases/proper-name forms were localized where needed.
- A separate 120-question bank was found in the upload and is kept as additional source material. It is not silently activated for non-Turkish languages because it does not contain verified multilingual translations.

## Name-City-Animal rules

The implementation is server authoritative:
1. Both players must be ready.
2. The game has 5 rounds.
3. Each round selects one playable letter for the selected language.
4. Both players submit Name, City and Animal simultaneously.
5. Empty answers score 0.
6. Answers that are not in the language dictionary score 0.
7. Answers that do not begin with the round letter score 0.
8. A valid answer unique to one player scores 2.
9. The same valid answer from both players scores 1 each.
10. The server resolves the round; the client cannot award itself points.
11. Each round is timed at 45 seconds. On timeout, missing answers are inserted as blanks and resolved as zero.
12. After 5 rounds, the higher cumulative score wins; equal scores are a draw.
13. Word normalization handles case, accents/diacritics and common Unicode forms without accepting incomplete spellings.

The scoring model is intentionally close to the classic Categories/Scattergories family: valid unique answers are rewarded more strongly than matching answers, and invalid/blank answers receive no points.

## Name-City-Animal dictionary coverage

The bundled curated dictionary contains 1,004 entries:
- TR: 227
- EN: 174
- DE: 194
- ES: 195
- FR: 214

The round-letter selector only chooses letters for which the current language has dictionary coverage across all three categories.

## Search audit

The country search already filtered by country name and ISO code.
The city/region picker had a real bug: its TextFields computed filtered lists from the controller but did not call `setState` on text changes. Typing therefore did not refresh the visible list. The release patch adds `onChanged: (_) => setState(() {})` to all three offline region/city search fields.

## Word-chain language audit

The Flutter client already exposes TR/EN/DE/ES/FR and the server RPC is the authority for word validation. However, the uploaded project does **not** contain the production implementation of `submit_word_game_word` or its dictionary table; the existing `word_data/README.md` explicitly says that those production definitions are external to this upload. Therefore this release patch does not pretend that the live word-chain dictionary has been fully verified.

The repository documents FrequencyWords/OpenSubtitles-derived dictionaries for the five supported languages. The production word-chain RPC should continue to use a language-specific dictionary and server-side normalization.

## Release migration order

Run Supabase migrations in this order after the existing Bestie migrations:

1. `20261006_game_content_most_likely.sql`
2. `20261006_game_content_trivia.sql`
3. `20261006_game_question_public_rpc.sql`
4. `20261006_name_city_animal.sql`

Then build the Flutter project and run the normal release/TestFlight/Play Store checks.

## Important deployment note

Flutter/Dart SDK was not available in the current execution environment, so a real `flutter analyze` / `flutter test` / device build could not be executed here. The patch was still checked for source-level structural balance, JSON validity, data uniqueness, and game-content invariants. A release build on the actual Flutter/Codemagic environment remains the final verification step.


## 2026-10-06 follow-up

### Name-City-Animal v2
- Expanded from 3 to 6 categories: Name, City, Animal, Plant, Thing, Country.
- Added localized dictionaries for TR/EN/DE/ES/FR.
- Server validation and duplicate scoring now apply to all 6 categories.
- SQL seed was split by language because Supabase SQL Editor rejected the original large script with `Query is too large to be run via the SQL Editor`.
- Base migration is ~26 KB; each language seed is ~10–13 KB.

### Calls / screen sharing
- Source audit confirms the current Flutter call surface is wired to the self-hosted mediasoup client.
- Camera, microphone, remote camera, remote screen, screen producer and optional screen-audio producer paths are present.
- This remains a source-level audit: no physical two-device call or OS-level screen-capture permission test was possible in the current environment.
- Android system playback audio is not claimed as guaranteed; it requires native playback-capture integration when the OS/plugin does not provide a display audio track.
