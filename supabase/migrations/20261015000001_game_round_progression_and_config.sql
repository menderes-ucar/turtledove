-- Bestie game progression/configuration hardening (Trivia + Most Likely To)
BEGIN;

CREATE OR REPLACE FUNCTION public.bestie_create_or_join_game_session_v4(
  p_game_type text,
  p_partner_id uuid,
  p_categories text[] DEFAULT '{}'::text[],
  p_total_rounds integer DEFAULT 15
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  me uuid := auth.uid();
  s public.game_sessions%ROWTYPE;
  rel uuid;
  cats text[] := COALESCE(p_categories, '{}'::text[]);
BEGIN
  IF me IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF p_partner_id IS NULL OR p_partner_id = me THEN RAISE EXCEPTION 'INVALID_PARTNER'; END IF;
  IF p_game_type NOT IN ('most_likely_to', 'trivia') THEN RAISE EXCEPTION 'INVALID_GAME_TYPE'; END IF;
  IF p_total_rounds NOT IN (5, 10, 15, 20, 25) THEN RAISE EXCEPTION 'INVALID_TOTAL_ROUNDS'; END IF;
  IF cardinality(cats) < 1 OR cardinality(cats) > 5 THEN RAISE EXCEPTION 'INVALID_CATEGORIES'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = me AND paired_with = p_partner_id
  ) THEN RAISE EXCEPTION 'NOT_PAIRED'; END IF;

  SELECT * INTO s
  FROM public.game_sessions
  WHERE game_type = p_game_type
    AND status IN ('waiting', 'playing')
    AND ((created_by = me AND partner_id = p_partner_id)
      OR (created_by = p_partner_id AND partner_id = me))
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF FOUND THEN
    INSERT INTO public.game_players(session_id, user_id, relationship_id)
    SELECT s.id, x, s.relationship_id
    FROM (VALUES (me), (p_partner_id)) v(x)
    ON CONFLICT DO NOTHING;
    RETURN to_jsonb(s);
  END IF;

  rel := public.bestie_relationship_id_v3(me, p_partner_id);
  INSERT INTO public.game_sessions(
    game_type, status, created_by, partner_id, current_round,
    total_rounds, categories, relationship_id
  )
  VALUES (
    p_game_type, 'waiting', me, p_partner_id, 1,
    p_total_rounds, cats, rel
  )
  RETURNING * INTO s;

  INSERT INTO public.game_players(session_id, user_id, relationship_id)
  VALUES (s.id, me, rel), (s.id, p_partner_id, rel)
  ON CONFLICT DO NOTHING;

  RETURN to_jsonb(s);
END;
$$;

REVOKE ALL ON FUNCTION public.bestie_create_or_join_game_session_v4(text, uuid, text[], integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bestie_create_or_join_game_session_v4(text, uuid, text[], integer) TO authenticated;

-- Keep categories balanced: choose a question from the least-used selected
-- category first; within that category prefer unseen prompts for this pair.
CREATE OR REPLACE FUNCTION public.bestie_game_pick_question_v3(p_session_id uuid)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  s record;
  qid uuid;
  chosen_category text;
BEGIN
  SELECT * INTO s FROM public.game_sessions WHERE id = p_session_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_SESSION_NOT_FOUND'; END IF;

  SELECT q.category INTO chosen_category
  FROM public.game_questions q
  WHERE q.game_type = s.game_type
    AND q.is_active = true
    AND (COALESCE(cardinality(s.categories), 0) = 0 OR q.category = ANY(s.categories))
  GROUP BY q.category
  ORDER BY (
    SELECT count(*)
    FROM public.game_rounds gr
    JOIN public.game_questions used_q ON used_q.id = gr.question_id
    WHERE gr.session_id = p_session_id AND used_q.category = q.category
  ) ASC, random()
  LIMIT 1;

  SELECT q.id INTO qid
  FROM public.game_questions q
  WHERE q.game_type = s.game_type
    AND q.is_active = true
    AND (COALESCE(cardinality(s.categories), 0) = 0 OR q.category = ANY(s.categories))
    AND (chosen_category IS NULL OR q.category = chosen_category)
    AND NOT EXISTS (
      SELECT 1
      FROM public.game_rounds gr
      JOIN public.game_sessions used_s ON used_s.id = gr.session_id
      JOIN public.game_questions used_q ON used_q.id = gr.question_id
      WHERE used_s.game_type = s.game_type
        AND used_s.created_by IS NOT NULL
        AND used_s.partner_id IS NOT NULL
        AND LEAST(used_s.created_by, used_s.partner_id) = LEAST(s.created_by, s.partner_id)
        AND GREATEST(used_s.created_by, used_s.partner_id) = GREATEST(s.created_by, s.partner_id)
        AND (
          used_q.id = q.id OR
          lower(regexp_replace(trim(used_q.prompt), '\s+', ' ', 'g')) =
          lower(regexp_replace(trim(q.prompt), '\s+', ' ', 'g'))
        )
    )
  ORDER BY random()
  LIMIT 1;

  -- If the chosen category has been exhausted for this pair, use any unseen
  -- selected-category question before reusing a prompt.
  IF qid IS NULL THEN
    SELECT q.id INTO qid
    FROM public.game_questions q
    WHERE q.game_type = s.game_type
      AND q.is_active = true
      AND (COALESCE(cardinality(s.categories), 0) = 0 OR q.category = ANY(s.categories))
      AND NOT EXISTS (
        SELECT 1
        FROM public.game_rounds gr
        JOIN public.game_sessions used_s ON used_s.id = gr.session_id
        JOIN public.game_questions used_q ON used_q.id = gr.question_id
        WHERE used_s.game_type = s.game_type
          AND LEAST(used_s.created_by, used_s.partner_id) = LEAST(s.created_by, s.partner_id)
          AND GREATEST(used_s.created_by, used_s.partner_id) = GREATEST(s.created_by, s.partner_id)
          AND (used_q.id = q.id OR
            lower(regexp_replace(trim(used_q.prompt), '\s+', ' ', 'g')) =
            lower(regexp_replace(trim(q.prompt), '\s+', ' ', 'g')))
      )
    ORDER BY random()
    LIMIT 1;
  END IF;

  -- Reuse is allowed only when the pair exhausted all distinct prompts.
  IF qid IS NULL THEN
    SELECT q.id INTO qid
    FROM public.game_questions q
    WHERE q.game_type = s.game_type
      AND q.is_active = true
      AND (COALESCE(cardinality(s.categories), 0) = 0 OR q.category = ANY(s.categories))
    ORDER BY random()
    LIMIT 1;
  END IF;

  IF qid IS NULL THEN RAISE EXCEPTION 'NO_GAME_QUESTION_AVAILABLE'; END IF;
  RETURN qid;
END;
$$;

-- Both answers and both explicit confirmations are required. The first
-- confirmation is persisted; the second advances the shared session exactly once.
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
  player_count integer;
  confirmed_count integer;
BEGIN
  IF me IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  SELECT * INTO s
  FROM public.game_sessions
  WHERE id = p_session_id AND (created_by = me OR partner_id = me)
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_SESSION_NOT_FOUND'; END IF;

  SELECT * INTO r
  FROM public.game_rounds
  WHERE id = p_round_id AND session_id = p_session_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_ROUND_NOT_FOUND'; END IF;

  IF s.current_round > r.round_number OR s.status = 'completed' THEN
    RETURN (SELECT to_jsonb(gs) FROM public.game_sessions gs WHERE gs.id = p_session_id);
  END IF;
  IF s.current_round <> r.round_number THEN RAISE EXCEPTION 'ROUND_MISMATCH'; END IF;

  IF r.resolved_at IS NULL THEN
    PERFORM public.bestie_resolve_game_round_v3(p_round_id);
    SELECT * INTO r FROM public.game_rounds WHERE id = p_round_id FOR UPDATE;
  END IF;
  IF r.resolved_at IS NULL THEN RAISE EXCEPTION 'ROUND_NOT_READY'; END IF;

  UPDATE public.game_players
  SET round_confirmed = true
  WHERE session_id = p_session_id AND user_id = me;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_PLAYER_NOT_FOUND'; END IF;

  SELECT count(*)::integer,
         count(*) FILTER (WHERE coalesce(round_confirmed, false))::integer
  INTO player_count, confirmed_count
  FROM public.game_players
  WHERE session_id = p_session_id AND user_id IN (s.created_by, s.partner_id);

  IF player_count <> 2 THEN RAISE EXCEPTION 'GAME_PLAYERS_INCOMPLETE'; END IF;
  IF confirmed_count < 2 THEN
    RETURN (SELECT to_jsonb(gs) FROM public.game_sessions gs WHERE id = p_session_id);
  END IF;

  IF s.current_round >= s.total_rounds THEN
    UPDATE public.game_sessions SET status = 'completed', updated_at = now()
    WHERE id = p_session_id;
  ELSE
    next_round := s.current_round + 1;
    IF NOT EXISTS (
      SELECT 1 FROM public.game_rounds
      WHERE session_id = p_session_id AND round_number = next_round
    ) THEN
      qid := public.bestie_game_pick_question_v3(p_session_id);
      INSERT INTO public.game_rounds(session_id, round_number, question_id)
      VALUES (p_session_id, next_round, qid);
    END IF;

    UPDATE public.game_players SET round_confirmed = false
    WHERE session_id = p_session_id;
    UPDATE public.game_sessions
    SET current_round = next_round, status = 'playing', updated_at = now()
    WHERE id = p_session_id;
  END IF;

  RETURN (SELECT to_jsonb(gs) FROM public.game_sessions gs WHERE gs.id = p_session_id);
END;
$$;

REVOKE ALL ON FUNCTION public.bestie_advance_game_round_v4(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bestie_advance_game_round_v4(uuid, uuid) TO authenticated;

-- Translation rows exist in two historical shapes: Trivia uses an object with
-- prompt/options/correct, while Most Likely To uses a plain localized string.
-- Read both formats so users always see the language configured in their app.
CREATE OR REPLACE FUNCTION public.get_game_question_public_localized(
  p_question_id uuid,
  p_language_code text
)
RETURNS TABLE (
  id uuid,
  game_type text,
  category text,
  subcategory text,
  prompt text,
  question_type text,
  options jsonb,
  correct_answer text,
  difficulty text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  q public.game_questions%ROWTYPE;
  v_language text := lower(coalesce(nullif(trim(p_language_code), ''),
    (SELECT language_code FROM public.profiles WHERE id = auth.uid()), 'en'));
  v_translation jsonb;
BEGIN
  IF v_language NOT IN ('tr', 'en', 'de', 'es', 'fr') THEN v_language := 'en'; END IF;
  SELECT * INTO q FROM public.game_questions WHERE id = p_question_id AND is_active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_QUESTION_NOT_FOUND'; END IF;

  v_translation := q.translations -> v_language;
  IF v_translation IS NULL OR v_translation = 'null'::jsonb THEN
    v_translation := q.translations -> 'en';
  END IF;

  id := q.id;
  game_type := q.game_type;
  category := coalesce(
    CASE WHEN jsonb_typeof(v_translation) = 'object' THEN v_translation ->> 'category' END,
    q.category
  );
  subcategory := coalesce(
    CASE WHEN jsonb_typeof(v_translation) = 'object' THEN v_translation ->> 'subcategory' END,
    q.subcategory
  );
  prompt := coalesce(
    CASE WHEN jsonb_typeof(v_translation) = 'object' THEN v_translation ->> 'prompt' END,
    CASE WHEN jsonb_typeof(v_translation) = 'string' THEN trim(both '"' from v_translation::text) END,
    q.prompt
  );
  question_type := q.question_type;
  options := CASE
    WHEN jsonb_typeof(v_translation) = 'object' AND jsonb_typeof(v_translation -> 'options') = 'array'
      THEN v_translation -> 'options'
    ELSE q.options
  END;
  -- Never expose Trivia's answer key to the client.
  correct_answer := CASE WHEN q.game_type = 'trivia' THEN NULL ELSE q.correct_answer END;
  difficulty := q.difficulty;
  RETURN NEXT;
END;
$$;

-- Grade Trivia against each respondent's own localized answer key. This matters
-- when the two partners use different app languages.
CREATE OR REPLACE FUNCTION public.bestie_resolve_game_round_v3(p_round_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  r record;
  q public.game_questions%ROWTYPE;
  answer_row record;
  expected_answer text;
  same_choice boolean;
  answer_count integer;
BEGIN
  SELECT gr.*, gs.game_type, gs.created_by, gs.partner_id
  INTO r
  FROM public.game_rounds gr
  JOIN public.game_sessions gs ON gs.id = gr.session_id
  WHERE gr.id = p_round_id
    AND (gs.created_by = auth.uid() OR gs.partner_id = auth.uid())
  FOR UPDATE OF gr;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_ROUND_NOT_FOUND'; END IF;
  IF r.resolved_at IS NOT NULL THEN RETURN to_jsonb(r); END IF;

  SELECT count(DISTINCT ga.user_id)::integer INTO answer_count
  FROM public.game_answers ga
  WHERE ga.round_id = p_round_id
    AND ga.user_id IN (r.created_by, r.partner_id);
  IF answer_count < 2 THEN RETURN to_jsonb(r); END IF;

  SELECT * INTO q FROM public.game_questions WHERE id = r.question_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_QUESTION_NOT_FOUND'; END IF;

  IF r.game_type = 'trivia' THEN
    FOR answer_row IN
      SELECT ga.user_id, ga.answer
      FROM public.game_answers ga
      WHERE ga.round_id = p_round_id
    LOOP
      expected_answer := q.correct_answer;
      SELECT lower(coalesce(nullif(trim(p.language_code), ''), 'en'))
      INTO expected_answer
      FROM public.profiles p
      WHERE p.id = answer_row.user_id;
      expected_answer := coalesce(
        CASE
          WHEN q.translations -> coalesce(expected_answer, 'en') ->> 'correct' IS NOT NULL
            THEN q.translations -> coalesce(expected_answer, 'en') ->> 'correct'
          ELSE NULL
        END,
        q.correct_answer
      );
      UPDATE public.game_answers
      SET is_correct = lower(trim(answer_row.answer)) = lower(trim(coalesce(expected_answer, ''))),
          points = CASE
            WHEN lower(trim(answer_row.answer)) = lower(trim(coalesce(expected_answer, ''))) THEN 10
            ELSE 0
          END
      WHERE round_id = p_round_id AND user_id = answer_row.user_id;
    END LOOP;
  ELSE
    SELECT count(DISTINCT lower(trim(ga.answer))) = 1
    INTO same_choice
    FROM public.game_answers ga
    WHERE ga.round_id = p_round_id;
    UPDATE public.game_answers
    SET is_correct = same_choice,
        points = CASE WHEN same_choice THEN 10 ELSE 0 END
    WHERE round_id = p_round_id;
  END IF;

  UPDATE public.game_players gp
  SET score = gp.score + src.points
  FROM (
    SELECT user_id, SUM(coalesce(points, 0))::integer AS points
    FROM public.game_answers
    WHERE round_id = p_round_id
    GROUP BY user_id
  ) src
  WHERE gp.session_id = r.session_id AND gp.user_id = src.user_id;

  UPDATE public.game_rounds SET resolved_at = now() WHERE id = p_round_id;
  RETURN (SELECT to_jsonb(gr) FROM public.game_rounds gr WHERE gr.id = p_round_id);
END;
$$;

REVOKE ALL ON FUNCTION public.get_game_question_public_localized(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_game_question_public_localized(uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION public.bestie_resolve_game_round_v3(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bestie_resolve_game_round_v3(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
