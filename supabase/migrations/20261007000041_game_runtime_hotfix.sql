-- BESTIE GAME RUNTIME HOTFIX 41
-- Fixes the live-schema compatibility failures found during two-device testing.
--
-- 1. Name-City-Animal: older deployments have a legacy NOT NULL game_id on
--    name_city_animal_answers. The V3 engine uses session_id. The legacy
--    column is therefore made nullable so new V3 answers can be written.
-- 2. Name-City-Animal: the ready RPC starts the round atomically once both
--    players are ready, so the client does not depend on a realtime race.
-- 3. Word Chain: older game_word_sessions installations can have an old
--    status CHECK that rejects the V3 values waiting/playing/completed.
-- 4. Word Chain: the start RPC is made idempotent and ready-safe.
-- 5. Generic games: the ready RPC starts the game atomically when both
--    players are ready; existing V3 round logic remains unchanged.

BEGIN;

-- ============================================================================
-- WORD CHAIN: converge the legacy status constraint
-- ============================================================================

DO $$
DECLARE
  c record;
BEGIN
  IF to_regclass('public.game_word_sessions') IS NOT NULL THEN
    FOR c IN
      SELECT conname
      FROM pg_constraint
      WHERE conrelid = 'public.game_word_sessions'::regclass
        AND contype = 'c'
        AND pg_get_constraintdef(oid) ILIKE '%status%'
    LOOP
      EXECUTE format(
        'ALTER TABLE public.game_word_sessions DROP CONSTRAINT IF EXISTS %I',
        c.conname
      );
    END LOOP;

    ALTER TABLE public.game_word_sessions
      ALTER COLUMN status SET DEFAULT 'waiting';

    ALTER TABLE public.game_word_sessions
      ADD CONSTRAINT bestie_game_word_sessions_status_check_v3
      CHECK (status IN ('waiting','playing','completed'));
  END IF;
END $$;

-- ============================================================================
-- NAME-CITY-ANIMAL: legacy game_id compatibility
-- ============================================================================

DO $$
BEGIN
  IF to_regclass('public.name_city_animal_answers') IS NOT NULL THEN
    -- Older live schema has game_id NOT NULL. V3 stores the canonical game
    -- identity in session_id, so the legacy field must not block inserts.
    IF EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema='public'
        AND table_name='name_city_animal_answers'
        AND column_name='game_id'
    ) THEN
      ALTER TABLE public.name_city_animal_answers
        ALTER COLUMN game_id DROP NOT NULL;
    END IF;
  END IF;
END $$;

-- Recover session_id for legacy rows where game_id was actually the NCA
-- session identifier. Rows that cannot be mapped are intentionally preserved;
-- no historical answer is deleted.
DO $$
BEGIN
  IF to_regclass('public.name_city_animal_answers') IS NOT NULL
     AND to_regclass('public.name_city_animal_games') IS NOT NULL
     AND EXISTS (
       SELECT 1 FROM information_schema.columns
       WHERE table_schema='public' AND table_name='name_city_animal_answers'
         AND column_name='game_id'
     ) THEN
    UPDATE public.name_city_animal_answers a
    SET session_id = a.game_id
    WHERE a.session_id IS NULL
      AND a.game_id IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM public.name_city_animal_games g
        WHERE g.session_id = a.game_id
      );
  END IF;
END $$;

-- ============================================================================
-- NAME-CITY-ANIMAL: atomic ready/start transition
-- ============================================================================

CREATE OR REPLACE FUNCTION public.bestie_nca_ready_v3(
  p_ready boolean,
  p_session_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
  g record;
  me uuid := auth.uid();
  both_ready boolean;
  l text;
BEGIN
  IF me IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  SELECT * INTO g
  FROM public.name_city_animal_games
  WHERE session_id=p_session_id
    AND (created_by=me OR partner_id=me)
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'NCA_SESSION_NOT_FOUND'; END IF;
  IF g.status <> 'waiting' THEN
    RETURN public.bestie_nca_state_v3(p_session_id);
  END IF;

  IF me=g.created_by THEN
    UPDATE public.name_city_animal_games
    SET created_ready=p_ready,updated_at=now()
    WHERE session_id=p_session_id;
  ELSE
    UPDATE public.name_city_animal_games
    SET partner_ready=p_ready,updated_at=now()
    WHERE session_id=p_session_id;
  END IF;

  SELECT created_ready AND partner_ready
  INTO both_ready
  FROM public.name_city_animal_games
  WHERE session_id=p_session_id;

  IF both_ready THEN
    l := public.bestie_nca_pick_letter_v3(g.language_code);
    UPDATE public.name_city_animal_games
    SET status='playing',
        current_letter=COALESCE(NULLIF(current_letter,''),l),
        round_number=1,
        round_deadline_at=now()+interval '45 seconds',
        updated_at=now()
    WHERE session_id=p_session_id;
  END IF;

  RETURN public.bestie_nca_state_v3(p_session_id);
END;
$$;

-- ============================================================================
-- WORD CHAIN: atomic start, no stale waiting row
-- ============================================================================

CREATE OR REPLACE FUNCTION public.bestie_start_word_game_v3(
  p_session_id uuid,
  p_language_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
  s record;
  ready_count integer;
  existing record;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  SELECT * INTO s
  FROM public.game_sessions
  WHERE id=p_session_id
    AND (created_by=auth.uid() OR partner_id=auth.uid())
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_SESSION_NOT_FOUND'; END IF;

  SELECT count(*) FILTER (WHERE ready)::integer
  INTO ready_count
  FROM public.game_players
  WHERE session_id=p_session_id;

  IF ready_count < 2 THEN
    RETURN public.bestie_word_state_v3(p_session_id);
  END IF;

  SELECT * INTO existing
  FROM public.game_word_sessions
  WHERE session_id=p_session_id
  FOR UPDATE;

  IF FOUND AND existing.status='completed' THEN
    RETURN public.bestie_word_state_v3(p_session_id);
  END IF;

  INSERT INTO public.game_word_sessions(
    session_id,created_by,partner_id,language_code,required_letter,
    turn_user_id,turn_number,status,turn_started_at,turn_deadline_at,relationship_id
  ) VALUES(
    p_session_id,s.created_by,s.partner_id,
    lower(trim(p_language_code)),'A',s.created_by,1,
    'playing',now(),now()+interval '90 seconds',s.relationship_id
  )
  ON CONFLICT(session_id) DO UPDATE SET
    language_code=COALESCE(NULLIF(public.game_word_sessions.language_code,''),EXCLUDED.language_code),
    status=CASE
      WHEN public.game_word_sessions.status='completed' THEN public.game_word_sessions.status
      ELSE 'playing'
    END,
    turn_user_id=COALESCE(public.game_word_sessions.turn_user_id,EXCLUDED.turn_user_id),
    turn_number=GREATEST(COALESCE(public.game_word_sessions.turn_number,1),1),
    turn_started_at=COALESCE(public.game_word_sessions.turn_started_at,EXCLUDED.turn_started_at),
    turn_deadline_at=COALESCE(public.game_word_sessions.turn_deadline_at,EXCLUDED.turn_deadline_at),
    relationship_id=COALESCE(public.game_word_sessions.relationship_id,EXCLUDED.relationship_id),
    updated_at=now();

  UPDATE public.game_sessions
  SET status='playing',updated_at=now()
  WHERE id=p_session_id;

  RETURN public.bestie_word_state_v3(p_session_id);
END;
$$;

-- ============================================================================
-- GENERIC GAMES: ready action is authoritative, not Realtime-dependent
-- ============================================================================

CREATE OR REPLACE FUNCTION public.bestie_set_game_ready_v3(
  p_session_id uuid,
  p_ready boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
  me uuid := auth.uid();
  s record;
  both_ready boolean;
BEGIN
  IF me IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  UPDATE public.game_players gp
  SET ready=p_ready
  WHERE gp.session_id=p_session_id
    AND gp.user_id=me;
  IF NOT FOUND THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  SELECT count(*)=2 AND bool_and(coalesce(ready,false))
  INTO both_ready
  FROM public.game_players
  WHERE session_id=p_session_id;

  -- Word Chain owns its own start RPC because its state is stored in
  -- game_word_sessions. Do not create generic rounds for that game type.
  SELECT * INTO s
  FROM public.game_sessions
  WHERE id=p_session_id;

  IF FOUND AND s.game_type <> 'word_game' AND both_ready THEN
    RETURN public.bestie_start_game_if_ready_v3(p_session_id);
  END IF;

  RETURN public.bestie_game_get_session_v3(p_session_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.bestie_nca_ready_v3(boolean,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_start_word_game_v3(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_set_game_ready_v3(uuid,boolean) TO authenticated;

NOTIFY pgrst,'reload schema';

COMMIT;
