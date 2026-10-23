# Dove Deck — rules and release requirements

## Game rules (two-player partner match)
- Two paired users only; each starts with seven cards.
- The draw pile contains four suits (coral, ocean, leaf, sun), numbers 0–9 (one zero and two copies of 1–9 per suit), two Skip, two Reverse, and two Draw Two per suit, plus four Wild and four Wild Draw Four cards.
- The opening discard is a number card.
- A legal card matches the active suit or the top number. Wild cards may always be played; a color must be chosen.
- Skip and Reverse both skip the other player in a two-player match.
- Draw Two and Wild Draw Four make the opponent draw two/four cards and lose their turn. Stacking is not allowed.
- Drawing one card ends the current player's action; the player passes after drawing. No play-after-draw rule.
- First player to empty their hand wins. A future score mode may count remaining cards, but is not part of this initial ruleset.
- If the draw pile empties, shuffle the discard pile except its top card to form a new draw pile.
- The first release targets exactly two players, not 3–4 players.

## Release gates — not yet certified
- [ ] Authoritative server-side deal and move validation; clients must never submit arbitrary state.
- [ ] Pair relationship validated against the current profile relationship on every RPC.
- [ ] Hand privacy: each player sees their own hand; opponent hand is represented by a count only.
- [ ] Invite/accept UX and game discovery from the existing home games section.
- [ ] Realtime reconnect/resync, duplicate action/idempotency protection, stale-version recovery.
- [ ] Test SQL rules and Flutter rules, including simultaneous moves and invalid requests.
- [ ] Run formatter, analyzer, unit tests, Android/iOS builds.
- [ ] Verify RLS and realtime publication settings in a staging Supabase project.
- [ ] Validate accessibility, localization, and card visuals on real device sizes.
