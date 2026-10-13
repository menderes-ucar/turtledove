# Word Game Dictionaries

The client supports `tr`, `en`, `de`, `es`, and `fr`. Run `python tools/prepare_word_game_dictionaries.py` on a machine with internet access. The script first tries the 2018 full list and falls back to the published 50k list. It cleans tokens and emits one CSV per language.

The current uploaded project does not contain the existing production definition of `submit_word_game_word` or its dictionary table. This patch therefore does **not** overwrite that RPC. Import the generated CSV into the existing dictionary table using the table/schema already used by your Supabase RPC.

Source: FrequencyWords (OpenSubtitles-derived). The repository states that the processed content is CC-BY-SA-4.0. Keep attribution and comply with the ShareAlike terms for the database distribution.
