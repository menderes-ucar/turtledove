-- Repair the shared round-advance RPC. Apply in Supabase SQL Editor.
-- Both players must confirm the same resolved round; the second confirmation
-- atomically creates/activates the next round. Repeated calls are idempotent.
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
  v_user uuid := auth.uid();
  v_session public.game_sessions%ROWTYPE;
  v_round public.game_rounds%ROWTYPE;
  v_next_round integer;
  v_player_count integer;
  v_confirmed_count integer;
  v_question_id uuid;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  SELECT gs.* INTO v_session
  FROM public.game_sessions gs
  WHERE gs.id = p_session_id
    AND v_user IN (gs.created_by, gs.partner_id)
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_SESSION_NOT_FOUND'; END IF;

  SELECT gr.* INTO v_round
  FROM public.game_rounds gr
  WHERE gr.id = p_round_id AND gr.session_id = p_session_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_ROUND_NOT_FOUND'; END IF;

  -- If the other player already advanced this session, return its current state.
  IF v_session.current_round > v_round.round_number OR v_session.status = 'completed' THEN
    RETURN (SELECT to_jsonb(gs) FROM public.game_sessions gs WHERE gs.id = p_session_id);
  END IF;
  IF v_session.current_round <> v_round.round_number THEN
    RAISE EXCEPTION 'ROUND_MISMATCH';
  END IF;

  IF v_round.resolved_at IS NULL THEN
    PERFORM public.bestie_resolve_game_round_v3(p_round_id);
    SELECT gr.* INTO v_round FROM public.game_rounds gr WHERE gr.id = p_round_id;
    IF v_round.resolved_at IS NULL THEN RAISE EXCEPTION 'ROUND_NOT_RESOLVED'; END IF;
  END IF;

  UPDATE public.game_players gp
  SET round_confirmed = true
  WHERE gp.session_id = p_session_id AND gp.user_id = v_user;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_PLAYER_NOT_FOUND'; END IF;

  SELECT count(*)::integer,
         count(*) FILTER (WHERE gp.round_confirmed IS TRUE)::integer
  INTO v_player_count, v_confirmed_count
  FROM public.game_players gp
  WHERE gp.session_id = p_session_id
    AND gp.user_id IN (v_session.created_by, v_session.partner_id);

  IF v_player_count <> 2 THEN RAISE EXCEPTION 'GAME_PLAYERS_INCOMPLETE'; END IF;

  IF v_confirmed_count < 2 THEN
    RETURN (SELECT to_jsonb(gs) FROM public.game_sessions gs WHERE gs.id = p_session_id);
  END IF;

  IF v_session.current_round >= v_session.total_rounds THEN
    UPDATE public.game_sessions
    SET status = 'completed', updated_at = now()
    WHERE id = p_session_id;
  ELSE
    v_next_round := v_session.current_round + 1;

    SELECT gr.question_id INTO v_question_id
    FROM public.game_rounds gr
    WHERE gr.session_id = p_session_id AND gr.round_number = v_next_round;

    IF v_question_id IS NULL THEN
      v_question_id := public.bestie_game_pick_question_v3(p_session_id);
      IF v_question_id IS NULL THEN RAISE EXCEPTION 'NO_GAME_QUESTION_AVAILABLE'; END IF;
      INSERT INTO public.game_rounds(session_id, round_number, question_id)
      VALUES (p_session_id, v_next_round, v_question_id);
    END IF;

    UPDATE public.game_players
    SET round_confirmed = false
    WHERE session_id = p_session_id;

    UPDATE public.game_sessions
    SET current_round = v_next_round, status = 'playing', updated_at = now()
    WHERE id = p_session_id;
  END IF;

  RETURN (SELECT to_jsonb(gs) FROM public.game_sessions gs WHERE gs.id = p_session_id);
END;
$$;

REVOKE ALL ON FUNCTION public.bestie_advance_game_round_v4(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bestie_advance_game_round_v4(uuid, uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
