-- Fix synchronized round confirmation and prevent duplicate question text
-- across sessions for the same pair until the available pool is exhausted.

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
BEGIN
  SELECT * INTO s
  FROM public.game_sessions
  WHERE id = p_session_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'GAME_SESSION_NOT_FOUND';
  END IF;

  -- Prefer a question whose ID and visible prompt have not been used by this
  -- pair for this game type. Prompt comparison also avoids duplicate seed rows.
  SELECT q.id INTO qid
  FROM public.game_questions q
  WHERE q.game_type = s.game_type
    AND q.is_active = true
    AND (
      COALESCE(array_length(s.categories, 1), 0) = 0
      OR q.category = ANY(s.categories)
    )
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
          used_q.id = q.id
          OR lower(regexp_replace(trim(used_q.prompt), '\s+', ' ', 'g'))
             = lower(regexp_replace(trim(q.prompt), '\s+', ' ', 'g'))
        )
    )
  ORDER BY random()
  LIMIT 1;

  -- Reuse is allowed only after the pair has exhausted all distinct prompts
  -- in the selected categories.
  IF qid IS NULL THEN
    SELECT q.id INTO qid
    FROM public.game_questions q
    WHERE q.game_type = s.game_type
      AND q.is_active = true
      AND (
        COALESCE(array_length(s.categories, 1), 0) = 0
        OR q.category = ANY(s.categories)
      )
    ORDER BY random()
    LIMIT 1;
  END IF;

  IF qid IS NULL THEN
    RAISE EXCEPTION 'NO_GAME_QUESTION_AVAILABLE';
  END IF;

  RETURN qid;
END;
$$;

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

  -- Serialize both users' confirmations on the same session row.
  SELECT * INTO s
  FROM public.game_sessions
  WHERE id = p_session_id
    AND (created_by = me OR partner_id = me)
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_SESSION_NOT_FOUND'; END IF;

  SELECT * INTO r
  FROM public.game_rounds
  WHERE id = p_round_id
    AND session_id = p_session_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_ROUND_NOT_FOUND'; END IF;

  -- Idempotency: if the partner already advanced, return the current session.
  IF s.current_round > r.round_number OR s.status = 'completed' THEN
    RETURN (SELECT to_jsonb(gs) FROM public.game_sessions gs WHERE gs.id = p_session_id);
  END IF;

  IF s.current_round <> r.round_number THEN
    RAISE EXCEPTION 'ROUND_MISMATCH';
  END IF;

  IF r.resolved_at IS NULL THEN
    PERFORM public.bestie_resolve_game_round_v3(p_round_id);
  END IF;

  UPDATE public.game_players
  SET round_confirmed = true
  WHERE session_id = p_session_id
    AND user_id = me;

  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_PLAYER_NOT_FOUND'; END IF;

  SELECT count(*)::integer,
         count(*) FILTER (WHERE coalesce(round_confirmed, false))::integer
    INTO player_count, confirmed_count
  FROM public.game_players
  WHERE session_id = p_session_id
    AND user_id IN (s.created_by, s.partner_id);

  IF player_count <> 2 THEN
    RAISE EXCEPTION 'GAME_PLAYERS_INCOMPLETE';
  END IF;

  -- First confirmation is persisted; wait for the second player's confirmation.
  IF confirmed_count < 2 THEN
    RETURN (SELECT to_jsonb(gs) FROM public.game_sessions gs WHERE gs.id = p_session_id);
  END IF;

  IF s.current_round >= s.total_rounds THEN
    UPDATE public.game_sessions
    SET status = 'completed', updated_at = now()
    WHERE id = p_session_id;
  ELSE
    next_round := s.current_round + 1;

    IF NOT EXISTS (
      SELECT 1 FROM public.game_rounds
      WHERE session_id = p_session_id
        AND round_number = next_round
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

REVOKE ALL ON FUNCTION public.bestie_advance_game_round_v4(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bestie_advance_game_round_v4(uuid, uuid) TO authenticated;
