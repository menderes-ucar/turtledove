-- BESTIE 43: multiplayer runtime hardening
--
-- Fixes included:
-- 1) game_players RLS recursion (again, idempotently) using a SECURITY DEFINER
--    helper that reads only game_sessions.
-- 2) Most Likely To / Trivia: both players must explicitly confirm the result
--    before the next round is created.
-- 3) Name-City-Animal: legacy game_id is made nullable/synchronised; the
--    runtime moves from answering -> reviewing -> next round only after BOTH
--    players review the opponent's six categories.
-- 4) NCA validation remains server-side and reviewer approval can never turn an
--    invalid dictionary answer into a valid answer.
-- 5) Realtime tables remain published.

BEGIN;

-- ============================================================================
-- GENERIC GAMES: RLS WITHOUT game_players SELF-REFERENCE
-- ============================================================================

CREATE OR REPLACE FUNCTION public.bestie_can_access_game_session_v43(p_session_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.game_sessions s
    WHERE s.id = p_session_id
      AND (s.created_by = auth.uid() OR s.partner_id = auth.uid())
  );
$$;

REVOKE ALL ON FUNCTION public.bestie_can_access_game_session_v43(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bestie_can_access_game_session_v43(uuid) TO authenticated;

DO $$
DECLARE
  p record;
BEGIN
  IF to_regclass('public.game_players') IS NULL THEN
    RETURN;
  END IF;

  FOR p IN
    SELECT polname
    FROM pg_policy
    WHERE polrelid = 'public.game_players'::regclass
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.game_players', p.polname);
  END LOOP;
END $$;

CREATE POLICY bestie_game_players_select_v43
ON public.game_players
FOR SELECT TO authenticated
USING (public.bestie_can_access_game_session_v43(session_id));

CREATE POLICY bestie_game_players_insert_v43
ON public.game_players
FOR INSERT TO authenticated
WITH CHECK (
  user_id = auth.uid()
  AND public.bestie_can_access_game_session_v43(session_id)
);

CREATE POLICY bestie_game_players_update_v43
ON public.game_players
FOR UPDATE TO authenticated
USING (
  user_id = auth.uid()
  AND public.bestie_can_access_game_session_v43(session_id)
)
WITH CHECK (
  user_id = auth.uid()
  AND public.bestie_can_access_game_session_v43(session_id)
);

CREATE POLICY bestie_game_players_delete_v43
ON public.game_players
FOR DELETE TO authenticated
USING (
  user_id = auth.uid()
  AND public.bestie_can_access_game_session_v43(session_id)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.game_players TO authenticated;

-- Make the ready transition authoritative on the server. The second player's
-- ready click starts the game immediately; Realtime is only the UI transport.
CREATE OR REPLACE FUNCTION public.bestie_set_game_ready_v3(
  p_session_id uuid,
  p_ready boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  me uuid := auth.uid();
  s record;
  both_ready boolean;
BEGIN
  IF me IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  SELECT * INTO s
  FROM public.game_sessions
  WHERE id=p_session_id
    AND (created_by=me OR partner_id=me)
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_SESSION_NOT_FOUND'; END IF;

  UPDATE public.game_players
  SET ready=p_ready
  WHERE session_id=p_session_id AND user_id=me;
  IF NOT FOUND THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  SELECT count(*)=2 AND bool_and(coalesce(ready,false))
  INTO both_ready
  FROM public.game_players
  WHERE session_id=p_session_id;

  IF both_ready AND s.status='waiting' THEN
    IF s.game_type='word_game' THEN
      PERFORM public.bestie_start_word_game_v3(
        p_session_id,
        COALESCE(NULLIF(s.category,''), COALESCE(s.categories[1], 'en'))
      );
    ELSE
      PERFORM public.bestie_start_game_if_ready_v3(p_session_id);
    END IF;
  END IF;

  RETURN (SELECT to_jsonb(gs) FROM public.game_sessions gs WHERE gs.id=p_session_id);
END;
$$;

REVOKE ALL ON FUNCTION public.bestie_set_game_ready_v3(uuid,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bestie_set_game_ready_v3(uuid,boolean) TO authenticated;

-- ============================================================================
-- GENERIC GAMES: BOTH PLAYERS CONFIRM BEFORE ADVANCING
-- ============================================================================

ALTER TABLE IF EXISTS public.game_players
  ADD COLUMN IF NOT EXISTS round_confirmed boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS bestie_game_players_round_confirmed_idx
  ON public.game_players(session_id, round_confirmed);

CREATE OR REPLACE FUNCTION public.bestie_advance_game_round_v4(
  p_session_id uuid,
  p_round_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  me uuid := auth.uid();
  s record;
  r record;
  qid uuid;
  next_round integer;
  confirmed_count integer;
BEGIN
  IF me IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  SELECT * INTO s
  FROM public.game_sessions
  WHERE id = p_session_id
    AND (created_by = me OR partner_id = me)
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_SESSION_NOT_FOUND'; END IF;

  SELECT * INTO r
  FROM public.game_rounds
  WHERE id = p_round_id AND session_id = p_session_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_ROUND_NOT_FOUND'; END IF;

  IF s.current_round > r.round_number THEN
    RETURN (SELECT to_jsonb(gs) FROM public.game_sessions gs WHERE gs.id = p_session_id);
  END IF;

  IF r.resolved_at IS NULL THEN
    PERFORM public.bestie_resolve_game_round_v3(p_round_id);
  END IF;

  -- The caller explicitly confirms this round. This is intentionally separate
  -- from player.ready: ready starts the game, round_confirmed advances it.
  UPDATE public.game_players
  SET round_confirmed = true
  WHERE session_id = p_session_id
    AND user_id = me;

  SELECT count(*) FILTER (WHERE coalesce(round_confirmed, false))::integer
  INTO confirmed_count
  FROM public.game_players
  WHERE session_id = p_session_id;

  -- One player may confirm early. The round stays visible until the other
  -- player confirms too.
  IF confirmed_count < 2 THEN
    RETURN (SELECT to_jsonb(gs) FROM public.game_sessions gs WHERE gs.id = p_session_id);
  END IF;

  IF s.current_round >= s.total_rounds THEN
    UPDATE public.game_sessions
    SET status = 'completed', updated_at = now()
    WHERE id = p_session_id;
  ELSE
    next_round := r.round_number + 1;

    IF NOT EXISTS (
      SELECT 1 FROM public.game_rounds
      WHERE session_id = p_session_id AND round_number = next_round
    ) THEN
      qid := public.bestie_game_pick_question_v3(p_session_id);
      INSERT INTO public.game_rounds(session_id, round_number, question_id)
      VALUES (p_session_id, next_round, qid);
    END IF;

    UPDATE public.game_players
    SET round_confirmed = false
    WHERE session_id = p_session_id;

    UPDATE public.game_sessions
    SET current_round = next_round,
        status = 'playing',
        updated_at = now()
    WHERE id = p_session_id;
  END IF;

  RETURN (SELECT to_jsonb(gs) FROM public.game_sessions gs WHERE gs.id = p_session_id);
END;
$$;

REVOKE ALL ON FUNCTION public.bestie_advance_game_round_v4(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bestie_advance_game_round_v4(uuid,uuid) TO authenticated;

-- ============================================================================
-- NAME-CITY-ANIMAL: LEGACY game_id COMPATIBILITY
-- ============================================================================

DO $$
BEGIN
  IF to_regclass('public.name_city_animal_answers') IS NULL THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'name_city_animal_answers'
      AND column_name = 'game_id'
  ) THEN
    ALTER TABLE public.name_city_animal_answers
      ALTER COLUMN game_id DROP NOT NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.name_city_animal_answers') IS NOT NULL
     AND to_regclass('public.name_city_animal_games') IS NOT NULL
     AND EXISTS (
       SELECT 1 FROM information_schema.columns
       WHERE table_schema='public'
         AND table_name='name_city_animal_answers'
         AND column_name='game_id'
     ) THEN
    UPDATE public.name_city_animal_answers a
    SET session_id = COALESCE(a.session_id, a.game_id)
    WHERE a.session_id IS NULL
      AND a.game_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.name_city_animal_games g
        WHERE g.session_id = a.game_id
      );
  END IF;
END $$;

-- Review state is stored on each answer row. NULL means "not reviewed yet".
ALTER TABLE IF EXISTS public.name_city_animal_answers
  ADD COLUMN IF NOT EXISTS name_review boolean,
  ADD COLUMN IF NOT EXISTS city_review boolean,
  ADD COLUMN IF NOT EXISTS animal_review boolean,
  ADD COLUMN IF NOT EXISTS plant_review boolean,
  ADD COLUMN IF NOT EXISTS thing_review boolean,
  ADD COLUMN IF NOT EXISTS country_review boolean,
  ADD COLUMN IF NOT EXISTS reviewed_at timestamptz;

ALTER TABLE IF EXISTS public.name_city_animal_games
  ADD COLUMN IF NOT EXISTS phase text NOT NULL DEFAULT 'answering';

DO $$
BEGIN
  IF to_regclass('public.name_city_animal_games') IS NOT NULL THEN
    UPDATE public.name_city_animal_games
    SET phase = CASE
      WHEN status = 'completed' THEN 'reviewing'
      ELSE COALESCE(NULLIF(phase, ''), 'answering')
    END;
  END IF;
END $$;

DO $$
DECLARE
  c record;
BEGIN
  IF to_regclass('public.name_city_animal_games') IS NULL THEN
    RETURN;
  END IF;
  FOR c IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'public.name_city_animal_games'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%phase%'
  LOOP
    EXECUTE format('ALTER TABLE public.name_city_animal_games DROP CONSTRAINT IF EXISTS %I', c.conname);
  END LOOP;
END $$;

ALTER TABLE IF EXISTS public.name_city_animal_games
  ADD CONSTRAINT bestie_nca_phase_check_v43
  CHECK (phase IN ('answering','reviewing'));

CREATE INDEX IF NOT EXISTS bestie_nca_review_idx
  ON public.name_city_animal_answers(session_id, round_number, reviewed_at);

-- ============================================================================
-- NAME-CITY-ANIMAL: STATE
-- ============================================================================

CREATE OR REPLACE FUNCTION public.bestie_nca_state_v4(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  g record;
  me uuid := auth.uid();
  created_submitted boolean;
  partner_submitted boolean;
  current_results jsonb;
  my_review_complete boolean;
  partner_review_complete boolean;
BEGIN
  SELECT * INTO g
  FROM public.name_city_animal_games
  WHERE session_id = p_session_id
    AND (created_by = me OR partner_id = me);
  IF NOT FOUND THEN RAISE EXCEPTION 'NCA_SESSION_NOT_FOUND'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.name_city_animal_answers a
    WHERE a.session_id=g.session_id AND a.round_number=g.round_number AND a.user_id=g.created_by
  ) INTO created_submitted;

  SELECT EXISTS (
    SELECT 1 FROM public.name_city_animal_answers a
    WHERE a.session_id=g.session_id AND a.round_number=g.round_number AND a.user_id=g.partner_id
  ) INTO partner_submitted;

  SELECT EXISTS (
    SELECT 1 FROM public.name_city_animal_answers a
    WHERE a.session_id=g.session_id AND a.round_number=g.round_number
      AND a.user_id <> me
      AND a.name_review IS NOT NULL
      AND a.city_review IS NOT NULL
      AND a.animal_review IS NOT NULL
      AND a.plant_review IS NOT NULL
      AND a.thing_review IS NOT NULL
      AND a.country_review IS NOT NULL
  ) INTO my_review_complete;

  SELECT EXISTS (
    SELECT 1 FROM public.name_city_animal_answers a
    WHERE a.session_id=g.session_id AND a.round_number=g.round_number
      AND a.user_id = me
      AND a.name_review IS NOT NULL
      AND a.city_review IS NOT NULL
      AND a.animal_review IS NOT NULL
      AND a.plant_review IS NOT NULL
      AND a.thing_review IS NOT NULL
      AND a.country_review IS NOT NULL
  ) INTO partner_review_complete;

  SELECT jsonb_agg(jsonb_build_object(
    'user_id',a.user_id,
    'name',a.name,'city',a.city,'animal',a.animal,'plant',a.plant,'thing',a.thing,'country',a.country,
    'name_valid',a.name_valid,'city_valid',a.city_valid,'animal_valid',a.animal_valid,
    'plant_valid',a.plant_valid,'thing_valid',a.thing_valid,'country_valid',a.country_valid,
    'name_review',a.name_review,'city_review',a.city_review,'animal_review',a.animal_review,
    'plant_review',a.plant_review,'thing_review',a.thing_review,'country_review',a.country_review,
    'points',a.points
  ) ORDER BY a.submitted_at)
  INTO current_results
  FROM public.name_city_animal_answers a
  WHERE a.session_id=g.session_id AND a.round_number=g.round_number;

  RETURN jsonb_build_object(
    'session_id',g.session_id,
    'created_by',g.created_by,
    'partner_id',g.partner_id,
    'language_code',g.language_code,
    'current_letter',g.current_letter,
    'round_number',g.round_number,
    'total_rounds',g.total_rounds,
    'status',g.status,
    'phase',g.phase,
    'round_deadline_at',g.round_deadline_at,
    'winner_user_id',g.winner_user_id,
    'created_ready',g.created_ready,
    'partner_ready',g.partner_ready,
    'created_score',g.created_score,
    'partner_score',g.partner_score,
    'created_submitted',created_submitted,
    'partner_submitted',partner_submitted,
    'my_review_complete',my_review_complete,
    'partner_review_complete',partner_review_complete,
    'round_results',COALESCE(current_results, g.last_round_results, '[]'::jsonb)
  );
END;
$$;

-- ============================================================================
-- NAME-CITY-ANIMAL: CREATE/JOIN + READY
-- ============================================================================

CREATE OR REPLACE FUNCTION public.bestie_create_nca_v4(
  p_language_code text,
  p_partner_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  me uuid := auth.uid();
  g record;
  rel uuid;
BEGIN
  IF me IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF p_language_code NOT IN ('tr','en','de','es','fr') THEN RAISE EXCEPTION 'UNSUPPORTED_LANGUAGE'; END IF;
  IF p_partner_id IS NULL OR p_partner_id = me THEN RAISE EXCEPTION 'INVALID_PARTNER'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=me AND paired_with=p_partner_id) THEN
    RAISE EXCEPTION 'NOT_PAIRED';
  END IF;

  SELECT * INTO g
  FROM public.name_city_animal_games
  WHERE status IN ('waiting','playing')
    AND ((created_by=me AND partner_id=p_partner_id) OR (created_by=p_partner_id AND partner_id=me))
  ORDER BY created_at DESC
  LIMIT 1;

  IF FOUND THEN
    RETURN public.bestie_nca_state_v4(g.session_id);
  END IF;

  rel := public.bestie_relationship_id_v3(me,p_partner_id);

  INSERT INTO public.name_city_animal_games(
    session_id,created_by,partner_id,language_code,current_letter,round_number,total_rounds,
    status,phase,created_ready,partner_ready,created_score,partner_score,last_round_results,relationship_id
  ) VALUES (
    gen_random_uuid(),me,p_partner_id,p_language_code,'A',1,5,
    'waiting','answering',false,false,0,0,'[]'::jsonb,rel
  ) RETURNING * INTO g;

  -- Legacy installations may still have game_id on the answer table. New rows
  -- use session_id as the canonical identity; game_id is kept compatible when
  -- the column exists.
  RETURN public.bestie_nca_state_v4(g.session_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_nca_ready_v4(
  p_session_id uuid,
  p_ready boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  g record;
  me uuid := auth.uid();
  both_ready boolean;
BEGIN
  SELECT * INTO g
  FROM public.name_city_animal_games
  WHERE session_id=p_session_id AND (created_by=me OR partner_id=me)
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'NCA_SESSION_NOT_FOUND'; END IF;
  IF g.status <> 'waiting' THEN RETURN public.bestie_nca_state_v4(p_session_id); END IF;

  IF me=g.created_by THEN
    UPDATE public.name_city_animal_games
    SET created_ready=p_ready,updated_at=now()
    WHERE session_id=p_session_id;
  ELSE
    UPDATE public.name_city_animal_games
    SET partner_ready=p_ready,updated_at=now()
    WHERE session_id=p_session_id;
  END IF;

  SELECT created_ready AND partner_ready INTO both_ready
  FROM public.name_city_animal_games WHERE session_id=p_session_id;

  IF both_ready THEN
    UPDATE public.name_city_animal_games
    SET status='playing',phase='answering',
        current_letter=public.bestie_nca_pick_letter_v3(language_code),
        round_number=1,
        round_deadline_at=now()+interval '45 seconds',
        updated_at=now()
    WHERE session_id=p_session_id;
  END IF;

  RETURN public.bestie_nca_state_v4(p_session_id);
END;
$$;

-- ============================================================================
-- NAME-CITY-ANIMAL: VALIDATION + REVIEW + ROUND TRANSITION
-- ============================================================================

CREATE OR REPLACE FUNCTION public.bestie_nca_validate_v4(
  p_language text,
  p_category text,
  p_word text,
  p_letter text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.bestie_nca_normalize_v3(p_word) <> ''
    AND left(public.bestie_nca_normalize_v3(p_word),1) = left(public.bestie_nca_normalize_v3(p_letter),1)
    AND EXISTS (
      SELECT 1 FROM public.name_city_animal_dictionary d
      WHERE d.language_code=p_language
        AND d.category=p_category
        AND d.normalized_word=public.bestie_nca_normalize_v3(p_word)
        AND d.is_active
    );
$$;

CREATE OR REPLACE FUNCTION public.bestie_nca_prepare_review_v4(p_session_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  g record;
BEGIN
  SELECT * INTO g FROM public.name_city_animal_games
  WHERE session_id=p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'NCA_SESSION_NOT_FOUND'; END IF;

  UPDATE public.name_city_animal_answers a SET
    name_valid=public.bestie_nca_validate_v4(g.language_code,'name',a.name,g.current_letter),
    city_valid=public.bestie_nca_validate_v4(g.language_code,'city',a.city,g.current_letter),
    animal_valid=public.bestie_nca_validate_v4(g.language_code,'animal',a.animal,g.current_letter),
    plant_valid=public.bestie_nca_validate_v4(g.language_code,'plant',a.plant,g.current_letter),
    thing_valid=public.bestie_nca_validate_v4(g.language_code,'thing',a.thing,g.current_letter),
    country_valid=public.bestie_nca_validate_v4(g.language_code,'country',a.country,g.current_letter),
    points=0,
    name_review=NULL,city_review=NULL,animal_review=NULL,
    plant_review=NULL,thing_review=NULL,country_review=NULL,
    reviewed_at=NULL
  WHERE a.session_id=g.session_id AND a.round_number=g.round_number;

  UPDATE public.name_city_animal_games
  SET phase='reviewing',round_deadline_at=NULL,updated_at=now()
  WHERE session_id=p_session_id AND status='playing';
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_expire_nca_v4(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  g record;
BEGIN
  SELECT * INTO g FROM public.name_city_animal_games
  WHERE session_id=p_session_id AND (created_by=auth.uid() OR partner_id=auth.uid())
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'NCA_SESSION_NOT_FOUND'; END IF;
  IF g.status <> 'playing' THEN RETURN public.bestie_nca_state_v4(p_session_id); END IF;
  IF g.phase <> 'answering' THEN RETURN public.bestie_nca_state_v4(p_session_id); END IF;
  IF now() < COALESCE(g.round_deadline_at,now()) THEN RETURN public.bestie_nca_state_v4(p_session_id); END IF;

  INSERT INTO public.name_city_animal_answers(
    session_id,round_number,user_id
  )
  SELECT p_session_id,g.round_number,g.created_by
  WHERE NOT EXISTS (
    SELECT 1 FROM public.name_city_animal_answers
    WHERE session_id=p_session_id AND round_number=g.round_number AND user_id=g.created_by
  );

  INSERT INTO public.name_city_animal_answers(
    session_id,round_number,user_id
  )
  SELECT p_session_id,g.round_number,g.partner_id
  WHERE NOT EXISTS (
    SELECT 1 FROM public.name_city_animal_answers
    WHERE session_id=p_session_id AND round_number=g.round_number AND user_id=g.partner_id
  );

  PERFORM public.bestie_nca_prepare_review_v4(p_session_id);
  RETURN public.bestie_nca_state_v4(p_session_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_submit_nca_v4(
  p_session_id uuid,
  p_name text,
  p_city text,
  p_animal text,
  p_plant text,
  p_thing text,
  p_country text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  g record;
  me uuid := auth.uid();
BEGIN
  SELECT * INTO g FROM public.name_city_animal_games
  WHERE session_id=p_session_id AND (created_by=me OR partner_id=me)
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'NCA_SESSION_NOT_FOUND'; END IF;
  IF g.status <> 'playing' OR g.phase <> 'answering' THEN RETURN public.bestie_nca_state_v4(p_session_id); END IF;
  IF now() > COALESCE(g.round_deadline_at,now()) THEN
    PERFORM public.bestie_nca_prepare_review_v4(p_session_id);
    RETURN public.bestie_nca_state_v4(p_session_id);
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.name_city_animal_answers
    WHERE session_id=p_session_id AND round_number=g.round_number AND user_id=me
  ) THEN
    RETURN public.bestie_nca_state_v4(p_session_id);
  END IF;

  INSERT INTO public.name_city_animal_answers(
    session_id,round_number,user_id,
    name,city,animal,plant,thing,country,
    name_normalized,city_normalized,animal_normalized,plant_normalized,thing_normalized,country_normalized
  ) VALUES (
    p_session_id,g.round_number,me,
    trim(coalesce(p_name,'')),trim(coalesce(p_city,'')),trim(coalesce(p_animal,'')),
    trim(coalesce(p_plant,'')),trim(coalesce(p_thing,'')),trim(coalesce(p_country,'')),
    public.bestie_nca_normalize_v3(p_name),public.bestie_nca_normalize_v3(p_city),public.bestie_nca_normalize_v3(p_animal),
    public.bestie_nca_normalize_v3(p_plant),public.bestie_nca_normalize_v3(p_thing),public.bestie_nca_normalize_v3(p_country)
  );

  RETURN public.bestie_nca_state_v4(p_session_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_review_nca_v4(
  p_session_id uuid,
  p_name_review boolean,
  p_city_review boolean,
  p_animal_review boolean,
  p_plant_review boolean,
  p_thing_review boolean,
  p_country_review boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  g record;
  target_user uuid;
  target record;
  other_review_complete boolean;
  created_points integer;
  partner_points integer;
  results jsonb;
  next_letter text;
BEGIN
  SELECT * INTO g FROM public.name_city_animal_games
  WHERE session_id=p_session_id AND (created_by=auth.uid() OR partner_id=auth.uid())
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'NCA_SESSION_NOT_FOUND'; END IF;
  IF g.status <> 'playing' OR g.phase <> 'reviewing' THEN
    RETURN public.bestie_nca_state_v4(p_session_id);
  END IF;

  target_user := CASE WHEN auth.uid()=g.created_by THEN g.partner_id ELSE g.created_by END;

  SELECT * INTO target
  FROM public.name_city_animal_answers
  WHERE session_id=p_session_id AND round_number=g.round_number AND user_id=target_user
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'NCA_TARGET_ANSWER_NOT_FOUND'; END IF;

  UPDATE public.name_city_animal_answers
  SET name_review=p_name_review,
      city_review=p_city_review,
      animal_review=p_animal_review,
      plant_review=p_plant_review,
      thing_review=p_thing_review,
      country_review=p_country_review,
      reviewed_at=now()
  WHERE id=target.id;

  SELECT count(*)=2
  FROM public.name_city_animal_answers a
  WHERE a.session_id=p_session_id
    AND a.round_number=g.round_number
    AND a.name_review IS NOT NULL
    AND a.city_review IS NOT NULL
    AND a.animal_review IS NOT NULL
    AND a.plant_review IS NOT NULL
    AND a.thing_review IS NOT NULL
    AND a.country_review IS NOT NULL
  INTO other_review_complete;

  IF NOT other_review_complete THEN
    RETURN public.bestie_nca_state_v4(p_session_id);
  END IF;

  -- Final score is the intersection of server validation and the opponent's
  -- review. A player cannot award points to an invalid dictionary answer.
  UPDATE public.name_city_animal_answers a
  SET points =
    CASE WHEN name_valid AND name_review THEN 2 ELSE 0 END +
    CASE WHEN city_valid AND city_review THEN 2 ELSE 0 END +
    CASE WHEN animal_valid AND animal_review THEN 2 ELSE 0 END +
    CASE WHEN plant_valid AND plant_review THEN 2 ELSE 0 END +
    CASE WHEN thing_valid AND thing_review THEN 2 ELSE 0 END +
    CASE WHEN country_valid AND country_review THEN 2 ELSE 0 END
  WHERE a.session_id=p_session_id AND a.round_number=g.round_number;

  SELECT * INTO target FROM public.name_city_animal_answers
  WHERE session_id=p_session_id AND round_number=g.round_number AND user_id=g.created_by;
  SELECT * INTO g FROM public.name_city_animal_games WHERE session_id=p_session_id FOR UPDATE;

  DECLARE
    partner_answer record;
  BEGIN
    SELECT * INTO partner_answer FROM public.name_city_animal_answers
    WHERE session_id=p_session_id AND round_number=g.round_number AND user_id=g.partner_id;

    -- Same valid answer earns 1 each instead of 2 each.
    IF target.name_valid AND partner_answer.name_valid AND target.name_review = true AND partner_answer.name_review = true AND public.bestie_nca_normalize_v3(target.name)=public.bestie_nca_normalize_v3(partner_answer.name) THEN
      UPDATE public.name_city_animal_answers SET points=GREATEST(points-1,0) WHERE id IN (target.id,partner_answer.id);
    END IF;
    IF target.city_valid AND partner_answer.city_valid AND target.city_review = true AND partner_answer.city_review = true AND public.bestie_nca_normalize_v3(target.city)=public.bestie_nca_normalize_v3(partner_answer.city) THEN
      UPDATE public.name_city_animal_answers SET points=GREATEST(points-1,0) WHERE id IN (target.id,partner_answer.id);
    END IF;
    IF target.animal_valid AND partner_answer.animal_valid AND target.animal_review = true AND partner_answer.animal_review = true AND public.bestie_nca_normalize_v3(target.animal)=public.bestie_nca_normalize_v3(partner_answer.animal) THEN
      UPDATE public.name_city_animal_answers SET points=GREATEST(points-1,0) WHERE id IN (target.id,partner_answer.id);
    END IF;
    IF target.plant_valid AND partner_answer.plant_valid AND target.plant_review = true AND partner_answer.plant_review = true AND public.bestie_nca_normalize_v3(target.plant)=public.bestie_nca_normalize_v3(partner_answer.plant) THEN
      UPDATE public.name_city_animal_answers SET points=GREATEST(points-1,0) WHERE id IN (target.id,partner_answer.id);
    END IF;
    IF target.thing_valid AND partner_answer.thing_valid AND target.thing_review = true AND partner_answer.thing_review = true AND public.bestie_nca_normalize_v3(target.thing)=public.bestie_nca_normalize_v3(partner_answer.thing) THEN
      UPDATE public.name_city_animal_answers SET points=GREATEST(points-1,0) WHERE id IN (target.id,partner_answer.id);
    END IF;
    IF target.country_valid AND partner_answer.country_valid AND target.country_review = true AND partner_answer.country_review = true AND public.bestie_nca_normalize_v3(target.country)=public.bestie_nca_normalize_v3(partner_answer.country) THEN
      UPDATE public.name_city_animal_answers SET points=GREATEST(points-1,0) WHERE id IN (target.id,partner_answer.id);
    END IF;
  END;

  SELECT COALESCE(points,0) INTO created_points
  FROM public.name_city_animal_answers
  WHERE session_id=p_session_id AND round_number=g.round_number AND user_id=g.created_by;
  SELECT COALESCE(points,0) INTO partner_points
  FROM public.name_city_animal_answers
  WHERE session_id=p_session_id AND round_number=g.round_number AND user_id=g.partner_id;

  SELECT jsonb_agg(jsonb_build_object(
    'user_id',a.user_id,'name',a.name,'city',a.city,'animal',a.animal,'plant',a.plant,'thing',a.thing,'country',a.country,
    'name_valid',a.name_valid,'city_valid',a.city_valid,'animal_valid',a.animal_valid,
    'plant_valid',a.plant_valid,'thing_valid',a.thing_valid,'country_valid',a.country_valid,
    'name_review',a.name_review,'city_review',a.city_review,'animal_review',a.animal_review,
    'plant_review',a.plant_review,'thing_review',a.thing_review,'country_review',a.country_review,
    'points',a.points
  ) ORDER BY a.submitted_at)
  INTO results
  FROM public.name_city_animal_answers a
  WHERE a.session_id=p_session_id AND a.round_number=g.round_number;

  IF g.round_number >= g.total_rounds THEN
    UPDATE public.name_city_animal_games
    SET created_score=g.created_score+created_points,
        partner_score=g.partner_score+partner_points,
        status='completed',
        winner_user_id=CASE
          WHEN g.created_score+created_points > g.partner_score+partner_points THEN g.created_by
          WHEN g.partner_score+partner_points > g.created_score+created_points THEN g.partner_id
          ELSE NULL
        END,
        phase='reviewing',
        last_round_results=COALESCE(results,'[]'::jsonb),
        round_deadline_at=NULL,
        updated_at=now()
    WHERE session_id=p_session_id;
  ELSE
    next_letter := public.bestie_nca_pick_letter_v3(g.language_code);
    UPDATE public.name_city_animal_games
    SET created_score=g.created_score+created_points,
        partner_score=g.partner_score+partner_points,
        round_number=g.round_number+1,
        current_letter=next_letter,
        phase='answering',
        round_deadline_at=now()+interval '45 seconds',
        last_round_results=COALESCE(results,'[]'::jsonb),
        updated_at=now()
    WHERE session_id=p_session_id;
  END IF;

  RETURN public.bestie_nca_state_v4(p_session_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_surrender_nca_v4(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public, pg_temp
AS $$
DECLARE
  g record;
BEGIN
  SELECT * INTO g FROM public.name_city_animal_games
  WHERE session_id=p_session_id AND (created_by=auth.uid() OR partner_id=auth.uid())
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'NCA_SESSION_NOT_FOUND'; END IF;

  UPDATE public.name_city_animal_games
  SET status='completed',round_deadline_at=NULL,updated_at=now(),
      winner_user_id=CASE WHEN created_by=auth.uid() THEN partner_id ELSE created_by END
  WHERE session_id=p_session_id;

  RETURN public.bestie_nca_state_v4(p_session_id);
END;
$$;

-- ============================================================================
-- REALTIME / GRANTS
-- ============================================================================

DO $$
BEGIN
  IF to_regclass('public.game_players') IS NOT NULL THEN
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.game_players; EXCEPTION WHEN duplicate_object THEN NULL; END;
  END IF;
  IF to_regclass('public.name_city_animal_games') IS NOT NULL THEN
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.name_city_animal_games; EXCEPTION WHEN duplicate_object THEN NULL; END;
  END IF;
  IF to_regclass('public.name_city_animal_answers') IS NOT NULL THEN
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.name_city_animal_answers; EXCEPTION WHEN duplicate_object THEN NULL; END;
  END IF;
  IF to_regclass('public.game_sessions') IS NOT NULL THEN
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.game_sessions; EXCEPTION WHEN duplicate_object THEN NULL; END;
  END IF;
  IF to_regclass('public.game_rounds') IS NOT NULL THEN
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.game_rounds; EXCEPTION WHEN duplicate_object THEN NULL; END;
  END IF;
  IF to_regclass('public.game_answers') IS NOT NULL THEN
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.game_answers; EXCEPTION WHEN duplicate_object THEN NULL; END;
  END IF;
  IF to_regclass('public.game_word_sessions') IS NOT NULL THEN
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.game_word_sessions; EXCEPTION WHEN duplicate_object THEN NULL; END;
  END IF;
  IF to_regclass('public.game_word_plays') IS NOT NULL THEN
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.game_word_plays; EXCEPTION WHEN duplicate_object THEN NULL; END;
  END IF;
END $$;

GRANT EXECUTE ON FUNCTION public.bestie_nca_state_v4(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_create_nca_v4(text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_nca_ready_v4(uuid,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_submit_nca_v4(uuid,text,text,text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_expire_nca_v4(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_review_nca_v4(uuid,boolean,boolean,boolean,boolean,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_surrender_nca_v4(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
