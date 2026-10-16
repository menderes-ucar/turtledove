-- Prevent question reuse across ALL historical sessions for the same pair and game type.
-- When the pair exhausts the eligible question pool, fail explicitly instead of repeating.
BEGIN;

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
  pair_lock_key text;
BEGIN
  SELECT * INTO s
  FROM public.game_sessions
  WHERE id = p_session_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_SESSION_NOT_FOUND'; END IF;
  IF s.created_by IS NULL OR s.partner_id IS NULL THEN
    RAISE EXCEPTION 'GAME_SESSION_PAIR_MISSING';
  END IF;

  -- Serialize question selection for this pair and game, even across separate sessions.
  pair_lock_key := s.game_type || ':' || LEAST(s.created_by::text, s.partner_id::text)
                            || ':' || GREATEST(s.created_by::text, s.partner_id::text);
  PERFORM pg_advisory_xact_lock(hashtextextended(pair_lock_key, 0));

  -- Prefer the least-used selected category in the current session, but only
  -- among categories with at least one unseen question for this pair.
  SELECT q.category INTO chosen_category
  FROM public.game_questions q
  WHERE q.game_type = s.game_type
    AND q.is_active = true
    AND (COALESCE(cardinality(s.categories), 0) = 0 OR q.category = ANY(s.categories))
    AND NOT EXISTS (
      SELECT 1
      FROM public.game_rounds old_gr
      JOIN public.game_sessions old_s ON old_s.id = old_gr.session_id
      JOIN public.game_questions old_q ON old_q.id = old_gr.question_id
      WHERE old_s.game_type = s.game_type
        AND LEAST(old_s.created_by::text, old_s.partner_id::text) = LEAST(s.created_by::text, s.partner_id::text)
        AND GREATEST(old_s.created_by::text, old_s.partner_id::text) = GREATEST(s.created_by::text, s.partner_id::text)
        AND (
          old_q.id = q.id OR
          lower(regexp_replace(trim(old_q.prompt), '\s+', ' ', 'g')) =
          lower(regexp_replace(trim(q.prompt), '\s+', ' ', 'g'))
        )
    )
  GROUP BY q.category
  ORDER BY (
    SELECT count(*)
    FROM public.game_rounds current_gr
    JOIN public.game_questions current_q ON current_q.id = current_gr.question_id
    WHERE current_gr.session_id = p_session_id AND current_q.category = q.category
  ) ASC, random()
  LIMIT 1;

  -- Pick an unseen question in the preferred category.
  SELECT q.id INTO qid
  FROM public.game_questions q
  WHERE q.game_type = s.game_type
    AND q.is_active = true
    AND (COALESCE(cardinality(s.categories), 0) = 0 OR q.category = ANY(s.categories))
    AND (chosen_category IS NULL OR q.category = chosen_category)
    AND NOT EXISTS (
      SELECT 1
      FROM public.game_rounds old_gr
      JOIN public.game_sessions old_s ON old_s.id = old_gr.session_id
      JOIN public.game_questions old_q ON old_q.id = old_gr.question_id
      WHERE old_s.game_type = s.game_type
        AND LEAST(old_s.created_by::text, old_s.partner_id::text) = LEAST(s.created_by::text, s.partner_id::text)
        AND GREATEST(old_s.created_by::text, old_s.partner_id::text) = GREATEST(s.created_by::text, s.partner_id::text)
        AND (
          old_q.id = q.id OR
          lower(regexp_replace(trim(old_q.prompt), '\s+', ' ', 'g')) =
          lower(regexp_replace(trim(q.prompt), '\s+', ' ', 'g'))
        )
    )
  ORDER BY random()
  LIMIT 1;

  -- If the preferred category has no unseen prompts, try any eligible unseen prompt.
  IF qid IS NULL THEN
    SELECT q.id INTO qid
    FROM public.game_questions q
    WHERE q.game_type = s.game_type
      AND q.is_active = true
      AND (COALESCE(cardinality(s.categories), 0) = 0 OR q.category = ANY(s.categories))
      AND NOT EXISTS (
        SELECT 1
        FROM public.game_rounds old_gr
        JOIN public.game_sessions old_s ON old_s.id = old_gr.session_id
        JOIN public.game_questions old_q ON old_q.id = old_gr.question_id
        WHERE old_s.game_type = s.game_type
          AND LEAST(old_s.created_by::text, old_s.partner_id::text) = LEAST(s.created_by::text, s.partner_id::text)
          AND GREATEST(old_s.created_by::text, old_s.partner_id::text) = GREATEST(s.created_by::text, s.partner_id::text)
          AND (
            old_q.id = q.id OR
            lower(regexp_replace(trim(old_q.prompt), '\s+', ' ', 'g')) =
            lower(regexp_replace(trim(q.prompt), '\s+', ' ', 'g'))
          )
      )
    ORDER BY random()
    LIMIT 1;
  END IF;

  IF qid IS NULL THEN
    RAISE EXCEPTION 'NO_UNSEEN_GAME_QUESTION_AVAILABLE'
      USING HINT = 'This pair has used all active questions in the selected categories for this game type. Add more questions or select other categories.';
  END IF;
  RETURN qid;
END;
$$;

REVOKE ALL ON FUNCTION public.bestie_game_pick_question_v3(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bestie_game_pick_question_v3(uuid) TO authenticated;

COMMIT;
