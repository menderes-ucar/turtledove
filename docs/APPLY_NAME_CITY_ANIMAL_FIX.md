# Bestie — Name City Animal production fix

The Flutter client calls these RPCs:
- create_or_join_name_city_animal_session(uuid,text)
- get_name_city_animal_state(uuid)
- set_name_city_animal_ready(uuid,boolean)
- start_name_city_animal(uuid)
- submit_name_city_animal_answers(uuid,text,text,text,text,text,text)
- expire_name_city_animal_round(uuid)
- surrender_name_city_animal(uuid)

The production database was missing `set_name_city_animal_ready(uuid,boolean)`. The supplied migration creates/replaces the complete Name-City-Animal backend and grants the RPCs to `authenticated`.

## Apply

From the project root:

```bash
supabase db push
```

If the SQL files are being applied manually in Supabase SQL Editor, run them in this order:

1. `20261006_name_city_animal.sql`
2. `20261006_name_city_animal_seed_tr.sql`
3. `20261006_name_city_animal_seed_en.sql`
4. `20261006_name_city_animal_seed_de.sql`
5. `20261006_name_city_animal_seed_es.sql`
6. `20261006_name_city_animal_seed_fr.sql`

After deployment, refresh the app and test:

1. Player A opens Name City Animal.
2. Player A taps `Hazırım`.
3. Player B opens the same session.
4. Player B taps `Hazırım`.
5. The server starts the game and selects a playable letter from the seeded dictionary.
6. Both players submit answers; the server validates and scores them.

Do not change the Flutter RPC parameter names. The migration matches the current Flutter service.
