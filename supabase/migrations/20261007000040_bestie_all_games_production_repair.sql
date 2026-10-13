-- BESTIE ALL GAMES PRODUCTION REPAIR
-- 2026-10-07
-- Built from the CURRENT uploaded lib.zip + supabase.zip.
--
-- Important design rules:
-- 1) Do not replace the old broken game RPCs. New V3 RPCs are used by the app.
-- 2) Existing game history is preserved.
-- 3) Pair history remains attached to the permanent relationship_pairs row.
-- 4) Round transitions are server-side and idempotent, so two devices cannot
--    accidentally skip a round by pressing Next at the same time.
-- 5) Name-City-Animal gets the columns its existing live table was missing
--    (notably session_id / round_number).

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================================
-- PERMANENT RELATIONSHIP HELPER
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.relationship_pairs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_a_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_b_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  first_paired_at timestamptz NOT NULL DEFAULT now(),
  last_paired_at timestamptz NOT NULL DEFAULT now(),
  ended_at timestamptz,
  is_active boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT bestie_relationship_pair_not_self CHECK (user_a_id <> user_b_id),
  CONSTRAINT bestie_relationship_pair_canonical CHECK (user_a_id < user_b_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS bestie_relationship_pair_uidx
  ON public.relationship_pairs(user_a_id, user_b_id);

CREATE OR REPLACE FUNCTION public.bestie_relationship_id_v3(
  p_user_id uuid,
  p_partner_id uuid
)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT rp.id
  FROM public.relationship_pairs rp
  WHERE rp.user_a_id = LEAST(p_user_id, p_partner_id)
    AND rp.user_b_id = GREATEST(p_user_id, p_partner_id)
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.bestie_relationship_id_v3(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bestie_relationship_id_v3(uuid,uuid) TO authenticated;

-- ============================================================================
-- GENERIC GAMES: SESSION / PLAYER / ROUND / ANSWER TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.game_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_type text NOT NULL,
  status text NOT NULL DEFAULT 'waiting',
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  partner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  current_round integer NOT NULL DEFAULT 1,
  total_rounds integer NOT NULL DEFAULT 15,
  categories text[] NOT NULL DEFAULT '{}'::text[],
  category text,
  subcategory text,
  relationship_id uuid REFERENCES public.relationship_pairs(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.game_sessions
  ADD COLUMN IF NOT EXISTS game_type text,
  ADD COLUMN IF NOT EXISTS status text DEFAULT 'waiting',
  ADD COLUMN IF NOT EXISTS created_by uuid,
  ADD COLUMN IF NOT EXISTS partner_id uuid,
  ADD COLUMN IF NOT EXISTS current_round integer DEFAULT 1,
  ADD COLUMN IF NOT EXISTS total_rounds integer DEFAULT 15,
  ADD COLUMN IF NOT EXISTS categories text[] DEFAULT '{}'::text[],
  ADD COLUMN IF NOT EXISTS category text,
  ADD COLUMN IF NOT EXISTS subcategory text,
  ADD COLUMN IF NOT EXISTS relationship_id uuid,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

CREATE INDEX IF NOT EXISTS bestie_game_sessions_pair_idx
  ON public.game_sessions(game_type, created_by, partner_id, status);
CREATE INDEX IF NOT EXISTS bestie_game_sessions_relationship_idx
  ON public.game_sessions(relationship_id);

CREATE TABLE IF NOT EXISTS public.game_players (
  session_id uuid NOT NULL REFERENCES public.game_sessions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  score integer NOT NULL DEFAULT 0,
  ready boolean NOT NULL DEFAULT false,
  mistakes integer NOT NULL DEFAULT 0,
  surrendered boolean NOT NULL DEFAULT false,
  joined_at timestamptz NOT NULL DEFAULT now(),
  relationship_id uuid,
  PRIMARY KEY (session_id, user_id)
);

ALTER TABLE public.game_players
  ADD COLUMN IF NOT EXISTS score integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS ready boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS mistakes integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS surrendered boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS joined_at timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS relationship_id uuid;

CREATE INDEX IF NOT EXISTS bestie_game_players_session_idx
  ON public.game_players(session_id);

CREATE TABLE IF NOT EXISTS public.game_rounds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES public.game_sessions(id) ON DELETE CASCADE,
  round_number integer NOT NULL,
  question_id uuid NOT NULL REFERENCES public.game_questions(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz
);

ALTER TABLE public.game_rounds
  ADD COLUMN IF NOT EXISTS session_id uuid,
  ADD COLUMN IF NOT EXISTS round_number integer DEFAULT 1,
  ADD COLUMN IF NOT EXISTS question_id uuid,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS resolved_at timestamptz;

CREATE INDEX IF NOT EXISTS bestie_game_rounds_session_round_idx
  ON public.game_rounds(session_id, round_number);

CREATE TABLE IF NOT EXISTS public.game_answers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  round_id uuid NOT NULL REFERENCES public.game_rounds(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  answer text NOT NULL,
  is_correct boolean,
  points integer NOT NULL DEFAULT 0,
  answered_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.game_answers
  ADD COLUMN IF NOT EXISTS round_id uuid,
  ADD COLUMN IF NOT EXISTS user_id uuid,
  ADD COLUMN IF NOT EXISTS answer text,
  ADD COLUMN IF NOT EXISTS is_correct boolean,
  ADD COLUMN IF NOT EXISTS points integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS answered_at timestamptz DEFAULT now();

CREATE INDEX IF NOT EXISTS bestie_game_answers_round_idx
  ON public.game_answers(round_id);

-- Existing game rows inherit the permanent pair where possible.
DO $$
BEGIN
  IF to_regclass('public.game_sessions') IS NOT NULL
     AND to_regclass('public.relationship_pairs') IS NOT NULL THEN
    UPDATE public.game_sessions gs
    SET relationship_id = rp.id
    FROM public.relationship_pairs rp
    WHERE gs.relationship_id IS NULL
      AND gs.created_by IS NOT NULL
      AND gs.partner_id IS NOT NULL
      AND rp.user_a_id = LEAST(gs.created_by,gs.partner_id)
      AND rp.user_b_id = GREATEST(gs.created_by,gs.partner_id);
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.game_players') IS NOT NULL
     AND to_regclass('public.game_sessions') IS NOT NULL THEN
    UPDATE public.game_players gp
    SET relationship_id = gs.relationship_id
    FROM public.game_sessions gs
    WHERE gp.relationship_id IS NULL
      AND gp.session_id = gs.id;
  END IF;
END $$;

-- ============================================================================
-- GENERIC GAME ENGINE (MOST LIKELY TO + TRIVIA)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.bestie_game_get_session_v3(p_session_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT to_jsonb(gs)
  FROM public.game_sessions gs
  WHERE gs.id = p_session_id
    AND (gs.created_by = auth.uid() OR gs.partner_id = auth.uid());
$$;

CREATE OR REPLACE FUNCTION public.bestie_game_get_players_v3(p_session_id uuid)
RETURNS SETOF public.game_players
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT gp.*
  FROM public.game_players gp
  JOIN public.game_sessions gs ON gs.id = gp.session_id
  WHERE gp.session_id = p_session_id
    AND (gs.created_by = auth.uid() OR gs.partner_id = auth.uid())
  ORDER BY gp.joined_at;
$$;

CREATE OR REPLACE FUNCTION public.bestie_game_get_answers_v3(p_round_id uuid)
RETURNS TABLE(
  round_id uuid,
  user_id uuid,
  answer text,
  answered_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT ga.round_id, ga.user_id, ga.answer, ga.answered_at
  FROM public.game_answers ga
  JOIN public.game_rounds gr ON gr.id=ga.round_id
  JOIN public.game_sessions gs ON gs.id=gr.session_id
  WHERE ga.round_id=p_round_id
    AND (gs.created_by=auth.uid() OR gs.partner_id=auth.uid())
  ORDER BY ga.answered_at;
$$;

CREATE OR REPLACE FUNCTION public.bestie_game_pick_question_v3(p_session_id uuid)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  s record;
  qid uuid;
BEGIN
  SELECT * INTO s FROM public.game_sessions WHERE id=p_session_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_SESSION_NOT_FOUND'; END IF;

  SELECT q.id INTO qid
  FROM public.game_questions q
  WHERE q.game_type=s.game_type
    AND q.is_active=true
    AND (
      COALESCE(array_length(s.categories,1),0)=0
      OR q.category=ANY(s.categories)
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.game_rounds gr
      JOIN public.game_sessions used_s ON used_s.id=gr.session_id
      WHERE used_s.game_type=s.game_type
        AND used_s.created_by IS NOT NULL
        AND used_s.partner_id IS NOT NULL
        AND LEAST(used_s.created_by,used_s.partner_id)=LEAST(s.created_by,s.partner_id)
        AND GREATEST(used_s.created_by,used_s.partner_id)=GREATEST(s.created_by,s.partner_id)
        AND gr.question_id=q.id
    )
  ORDER BY random()
  LIMIT 1;

  IF qid IS NULL THEN
    SELECT q.id INTO qid
    FROM public.game_questions q
    WHERE q.game_type=s.game_type
      AND q.is_active=true
      AND (
        COALESCE(array_length(s.categories,1),0)=0
        OR q.category=ANY(s.categories)
      )
    ORDER BY random()
    LIMIT 1;
  END IF;

  IF qid IS NULL THEN RAISE EXCEPTION 'NO_GAME_QUESTION_AVAILABLE'; END IF;
  RETURN qid;
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_create_or_join_game_session_v3(
  p_game_type text,
  p_partner_id uuid,
  p_categories text[] DEFAULT '{}'::text[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
  me uuid:=auth.uid();
  s record;
  rel uuid;
BEGIN
  IF me IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF p_partner_id IS NULL OR p_partner_id=me THEN RAISE EXCEPTION 'INVALID_PARTNER'; END IF;
  IF p_game_type NOT IN ('most_likely_to','trivia') THEN RAISE EXCEPTION 'INVALID_GAME_TYPE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=me AND paired_with=p_partner_id) THEN
    RAISE EXCEPTION 'NOT_PAIRED';
  END IF;

  SELECT * INTO s
  FROM public.game_sessions
  WHERE game_type=p_game_type
    AND status IN ('waiting','playing')
    AND ((created_by=me AND partner_id=p_partner_id)
      OR (created_by=p_partner_id AND partner_id=me))
  ORDER BY created_at DESC
  LIMIT 1;

  IF FOUND THEN
    INSERT INTO public.game_players(session_id,user_id,relationship_id)
    SELECT s.id, x, s.relationship_id
    FROM (VALUES(me),(p_partner_id)) v(x)
    ON CONFLICT DO NOTHING;
    RETURN to_jsonb(s);
  END IF;

  rel:=public.bestie_relationship_id_v3(me,p_partner_id);
  INSERT INTO public.game_sessions(
    game_type,status,created_by,partner_id,current_round,total_rounds,categories,relationship_id
  ) VALUES(
    p_game_type,'waiting',me,p_partner_id,1,15,COALESCE(p_categories,'{}'::text[]),rel
  ) RETURNING * INTO s;

  INSERT INTO public.game_players(session_id,user_id,relationship_id)
  VALUES(s.id,me,rel),(s.id,p_partner_id,rel)
  ON CONFLICT DO NOTHING;

  RETURN to_jsonb(s);
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_get_active_game_session_v3(
  p_game_type text,
  p_partner_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
  SELECT to_jsonb(gs)
  FROM public.game_sessions gs
  WHERE gs.game_type=p_game_type
    AND gs.status IN ('waiting','playing')
    AND ((gs.created_by=auth.uid() AND gs.partner_id=p_partner_id)
      OR (gs.created_by=p_partner_id AND gs.partner_id=auth.uid()))
  ORDER BY gs.created_at DESC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.bestie_set_game_ready_v3(
  p_session_id uuid,
  p_ready boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE me uuid:=auth.uid();
BEGIN
  IF me IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  UPDATE public.game_players gp
  SET ready=p_ready
  WHERE gp.session_id=p_session_id AND gp.user_id=me;
  IF NOT FOUND THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  RETURN public.bestie_game_get_session_v3(p_session_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_start_game_if_ready_v3(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
  s record;
  both_ready boolean;
  qid uuid;
BEGIN
  SELECT * INTO s
  FROM public.game_sessions
  WHERE id=p_session_id
    AND (created_by=auth.uid() OR partner_id=auth.uid())
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_SESSION_NOT_FOUND'; END IF;

  IF s.status='completed' OR s.status='playing' THEN
    RETURN to_jsonb(s);
  END IF;

  SELECT count(*)=2 AND bool_and(coalesce(ready,false))
  INTO both_ready
  FROM public.game_players
  WHERE session_id=p_session_id;

  IF NOT both_ready THEN RETURN to_jsonb(s); END IF;

  IF NOT EXISTS(SELECT 1 FROM public.game_rounds WHERE session_id=p_session_id AND round_number=1) THEN
    qid:=public.bestie_game_pick_question_v3(p_session_id);
    INSERT INTO public.game_rounds(session_id,round_number,question_id)
    VALUES(p_session_id,1,qid);
  END IF;

  UPDATE public.game_sessions
  SET status='playing',current_round=1,updated_at=now()
  WHERE id=p_session_id;

  SELECT * INTO s FROM public.game_sessions WHERE id=p_session_id;
  RETURN to_jsonb(s);
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_submit_game_answer_v3(
  p_round_id uuid,
  p_answer text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
  me uuid:=auth.uid();
  r record;
BEGIN
  IF me IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF trim(coalesce(p_answer,''))='' THEN RAISE EXCEPTION 'ANSWER_EMPTY'; END IF;

  SELECT gr.*,gs.created_by,gs.partner_id,gs.status AS session_status
  INTO r
  FROM public.game_rounds gr
  JOIN public.game_sessions gs ON gs.id=gr.session_id
  WHERE gr.id=p_round_id
    AND (gs.created_by=me OR gs.partner_id=me)
  FOR UPDATE OF gr;

  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_ROUND_NOT_FOUND'; END IF;
  IF r.resolved_at IS NOT NULL THEN RETURN jsonb_build_object('already_resolved',true); END IF;

  IF EXISTS(SELECT 1 FROM public.game_answers WHERE round_id=p_round_id AND user_id=me) THEN
    RETURN jsonb_build_object('already_answered',true);
  END IF;

  INSERT INTO public.game_answers(round_id,user_id,answer)
  VALUES(p_round_id,me,trim(p_answer));

  RETURN jsonb_build_object('round_id',p_round_id,'user_id',me,'answer',trim(p_answer));
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_resolve_game_round_v3(p_round_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
  r record;
  q record;
  first_answer text;
  second_answer text;
  first_user uuid;
  second_user uuid;
  same_choice boolean;
BEGIN
  SELECT gr.*,gs.game_type,gs.created_by,gs.partner_id
  INTO r
  FROM public.game_rounds gr
  JOIN public.game_sessions gs ON gs.id=gr.session_id
  WHERE gr.id=p_round_id
    AND (gs.created_by=auth.uid() OR gs.partner_id=auth.uid())
  FOR UPDATE OF gr;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_ROUND_NOT_FOUND'; END IF;
  IF r.resolved_at IS NOT NULL THEN RETURN to_jsonb(r); END IF;

  SELECT ga.user_id,ga.answer INTO first_user,first_answer
  FROM public.game_answers ga
  WHERE ga.round_id=p_round_id ORDER BY ga.answered_at LIMIT 1;

  SELECT ga.user_id,ga.answer INTO second_user,second_answer
  FROM public.game_answers ga
  WHERE ga.round_id=p_round_id ORDER BY ga.answered_at OFFSET 1 LIMIT 1;

  IF second_user IS NULL THEN RETURN to_jsonb(r); END IF;

  SELECT * INTO q FROM public.game_questions WHERE id=r.question_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_QUESTION_NOT_FOUND'; END IF;

  IF r.game_type='trivia' THEN
    UPDATE public.game_answers ga
    SET is_correct = lower(trim(ga.answer)) = lower(trim(coalesce(q.correct_answer,''))),
        points = CASE WHEN lower(trim(ga.answer)) = lower(trim(coalesce(q.correct_answer,''))) THEN 10 ELSE 0 END
    WHERE ga.round_id=p_round_id;
  ELSE
    same_choice:=lower(trim(first_answer))=lower(trim(second_answer));
    UPDATE public.game_answers
    SET is_correct=same_choice,
        points=CASE WHEN same_choice THEN 10 ELSE 0 END
    WHERE round_id=p_round_id;
  END IF;

  UPDATE public.game_players gp
  SET score=gp.score+src.points
  FROM (
    SELECT user_id,SUM(coalesce(points,0))::integer points
    FROM public.game_answers
    WHERE round_id=p_round_id GROUP BY user_id
  ) src
  WHERE gp.session_id=r.session_id AND gp.user_id=src.user_id;

  UPDATE public.game_rounds
  SET resolved_at=now()
  WHERE id=p_round_id;

  RETURN (SELECT to_jsonb(gr) FROM public.game_rounds gr WHERE gr.id=p_round_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_get_game_round_results_v3(p_round_id uuid)
RETURNS TABLE(
  user_id uuid,
  answer text,
  is_correct boolean,
  points integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
  SELECT ga.user_id,ga.answer,ga.is_correct,ga.points
  FROM public.game_answers ga
  JOIN public.game_rounds gr ON gr.id=ga.round_id
  JOIN public.game_sessions gs ON gs.id=gr.session_id
  WHERE ga.round_id=p_round_id
    AND (gs.created_by=auth.uid() OR gs.partner_id=auth.uid())
  ORDER BY ga.answered_at;
$$;

CREATE OR REPLACE FUNCTION public.bestie_advance_game_round_v3(
  p_session_id uuid,
  p_round_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
  s record;
  r record;
  qid uuid;
  next_round integer;
BEGIN
  SELECT * INTO s
  FROM public.game_sessions
  WHERE id=p_session_id
    AND (created_by=auth.uid() OR partner_id=auth.uid())
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_SESSION_NOT_FOUND'; END IF;

  SELECT * INTO r
  FROM public.game_rounds
  WHERE id=p_round_id AND session_id=p_session_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_ROUND_NOT_FOUND'; END IF;

  -- Another device may already have advanced the session.
  IF s.current_round > r.round_number THEN
    RETURN to_jsonb(s);
  END IF;

  IF r.resolved_at IS NULL THEN
    PERFORM public.bestie_resolve_game_round_v3(p_round_id);
  END IF;

  IF s.current_round >= s.total_rounds THEN
    UPDATE public.game_sessions
    SET status='completed',updated_at=now()
    WHERE id=p_session_id;
  ELSE
    next_round:=r.round_number+1;
    IF NOT EXISTS(
      SELECT 1 FROM public.game_rounds
      WHERE session_id=p_session_id AND round_number=next_round
    ) THEN
      qid:=public.bestie_game_pick_question_v3(p_session_id);
      INSERT INTO public.game_rounds(session_id,round_number,question_id)
      VALUES(p_session_id,next_round,qid);
    END IF;

    UPDATE public.game_sessions
    SET current_round=next_round,status='playing',updated_at=now()
    WHERE id=p_session_id;
  END IF;

  SELECT * INTO s FROM public.game_sessions WHERE id=p_session_id;
  RETURN to_jsonb(s);
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_count_unseen_game_questions_for_pair_v3(
  p_game_type text,
  p_partner_id uuid,
  p_categories text[] DEFAULT '{}'::text[]
)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
  SELECT count(*)::integer
  FROM public.game_questions q
  WHERE q.game_type=p_game_type
    AND q.is_active=true
    AND (
      COALESCE(array_length(p_categories,1),0)=0
      OR q.category=ANY(p_categories)
    )
    AND NOT EXISTS(
      SELECT 1
      FROM public.game_rounds gr
      JOIN public.game_sessions gs ON gs.id=gr.session_id
      WHERE gs.game_type=p_game_type
        AND LEAST(gs.created_by,gs.partner_id)=LEAST(auth.uid(),p_partner_id)
        AND GREATEST(gs.created_by,gs.partner_id)=GREATEST(auth.uid(),p_partner_id)
        AND gr.question_id=q.id
    );
$$;

-- ============================================================================
-- WORD GAME
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.game_word_sessions (
  session_id uuid PRIMARY KEY REFERENCES public.game_sessions(id) ON DELETE CASCADE,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  partner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  language_code text NOT NULL,
  required_letter text NOT NULL DEFAULT 'A',
  turn_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  turn_number integer NOT NULL DEFAULT 1,
  last_word text,
  turn_started_at timestamptz,
  turn_deadline_at timestamptz,
  status text NOT NULL DEFAULT 'waiting',
  winner_user_id uuid,
  loser_user_id uuid,
  end_reason text,
  last_error text,
  last_error_user_id uuid,
  relationship_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.game_word_sessions
  ADD COLUMN IF NOT EXISTS created_by uuid,
  ADD COLUMN IF NOT EXISTS partner_id uuid,
  ADD COLUMN IF NOT EXISTS language_code text,
  ADD COLUMN IF NOT EXISTS required_letter text DEFAULT 'A',
  ADD COLUMN IF NOT EXISTS turn_user_id uuid,
  ADD COLUMN IF NOT EXISTS turn_number integer DEFAULT 1,
  ADD COLUMN IF NOT EXISTS last_word text,
  ADD COLUMN IF NOT EXISTS turn_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS turn_deadline_at timestamptz,
  ADD COLUMN IF NOT EXISTS status text DEFAULT 'waiting',
  ADD COLUMN IF NOT EXISTS winner_user_id uuid,
  ADD COLUMN IF NOT EXISTS loser_user_id uuid,
  ADD COLUMN IF NOT EXISTS end_reason text,
  ADD COLUMN IF NOT EXISTS last_error text,
  ADD COLUMN IF NOT EXISTS last_error_user_id uuid,
  ADD COLUMN IF NOT EXISTS relationship_id uuid,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

CREATE TABLE IF NOT EXISTS public.game_word_plays (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES public.game_word_sessions(session_id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  turn_number integer NOT NULL,
  word text NOT NULL,
  normalized_word text NOT NULL,
  first_letter text NOT NULL,
  last_letter text NOT NULL,
  points integer NOT NULL DEFAULT 1,
  relationship_id uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.game_word_plays
  ADD COLUMN IF NOT EXISTS turn_number integer DEFAULT 1,
  ADD COLUMN IF NOT EXISTS word text,
  ADD COLUMN IF NOT EXISTS normalized_word text,
  ADD COLUMN IF NOT EXISTS first_letter text,
  ADD COLUMN IF NOT EXISTS last_letter text,
  ADD COLUMN IF NOT EXISTS points integer DEFAULT 1,
  ADD COLUMN IF NOT EXISTS relationship_id uuid,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

CREATE INDEX IF NOT EXISTS bestie_game_word_plays_session_idx
  ON public.game_word_plays(session_id,turn_number);
CREATE INDEX IF NOT EXISTS bestie_game_word_plays_relationship_idx
  ON public.game_word_plays(relationship_id);

DO $$
BEGIN
  IF to_regclass('public.relationship_pairs') IS NOT NULL
     AND to_regclass('public.game_word_sessions') IS NOT NULL THEN
    UPDATE public.game_word_sessions w
    SET relationship_id=rp.id
    FROM public.relationship_pairs rp
    WHERE w.relationship_id IS NULL
      AND w.created_by IS NOT NULL
      AND w.partner_id IS NOT NULL
      AND rp.user_a_id=LEAST(w.created_by,w.partner_id)
      AND rp.user_b_id=GREATEST(w.created_by,w.partner_id);
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.game_word_plays') IS NOT NULL
     AND to_regclass('public.game_word_sessions') IS NOT NULL THEN
    UPDATE public.game_word_plays p
    SET relationship_id=w.relationship_id
    FROM public.game_word_sessions w
    WHERE p.relationship_id IS NULL
      AND p.session_id=w.session_id;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.game_word_dictionary (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  language_code text NOT NULL,
  word text NOT NULL,
  normalized_word text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  UNIQUE(language_code,normalized_word)
);

CREATE OR REPLACE FUNCTION public.bestie_word_normalize_v3(input_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT translate(lower(trim(coalesce(input_text,''))),
    'ıİğĞüÜşŞöÖçÇâÂîÎûÛáÁéÉíÍóÓúÚäÄëËïÏñÑ',
    'iIgGuUsSoOcCaAiIuUaAeEiIoOuUaAeEiInN');
$$;

CREATE OR REPLACE FUNCTION public.bestie_word_state_v3(p_session_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
  SELECT to_jsonb(w)
  FROM public.game_word_sessions w
  WHERE w.session_id=p_session_id
    AND (w.created_by=auth.uid() OR w.partner_id=auth.uid());
$$;

CREATE OR REPLACE FUNCTION public.bestie_word_get_plays_v3(p_session_id uuid)
RETURNS SETOF public.game_word_plays
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
  SELECT p.* FROM public.game_word_plays p
  JOIN public.game_word_sessions w ON w.session_id=p.session_id
  WHERE p.session_id=p_session_id
    AND (w.created_by=auth.uid() OR w.partner_id=auth.uid())
  ORDER BY p.turn_number,p.created_at;
$$;

CREATE OR REPLACE FUNCTION public.bestie_create_or_join_word_game_session_v3(
  p_partner_id uuid,
  p_language_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
  me uuid:=auth.uid();
  s record;
  rel uuid;
BEGIN
  IF me IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF p_partner_id IS NULL OR p_partner_id=me THEN RAISE EXCEPTION 'INVALID_PARTNER'; END IF;
  IF p_language_code NOT IN ('tr','en','de','es','fr') THEN RAISE EXCEPTION 'UNSUPPORTED_LANGUAGE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=me AND paired_with=p_partner_id) THEN
    RAISE EXCEPTION 'NOT_PAIRED';
  END IF;

  SELECT * INTO s FROM public.game_sessions
  WHERE game_type='word_game'
    AND status IN ('waiting','playing')
    AND ((created_by=me AND partner_id=p_partner_id)
      OR (created_by=p_partner_id AND partner_id=me))
  ORDER BY created_at DESC LIMIT 1;

  IF NOT FOUND THEN
    rel:=public.bestie_relationship_id_v3(me,p_partner_id);
    INSERT INTO public.game_sessions(
      game_type,status,created_by,partner_id,current_round,total_rounds,categories,category,relationship_id
    ) VALUES('word_game','waiting',me,p_partner_id,1,1,ARRAY[p_language_code],p_language_code,rel)
    RETURNING * INTO s;
  ELSE
    UPDATE public.game_sessions
    SET category=COALESCE(category,p_language_code),
        categories=CASE WHEN categories IS NULL OR COALESCE(array_length(categories,1),0)=0 THEN ARRAY[p_language_code] ELSE categories END,
        relationship_id=COALESCE(relationship_id,public.bestie_relationship_id_v3(me,p_partner_id)),
        updated_at=now()
    WHERE id=s.id
    RETURNING * INTO s;
  END IF;

  INSERT INTO public.game_players(session_id,user_id,relationship_id)
  VALUES(s.id,me,s.relationship_id),(s.id,p_partner_id,s.relationship_id)
  ON CONFLICT DO NOTHING;

  INSERT INTO public.game_word_sessions(
    session_id,created_by,partner_id,language_code,required_letter,turn_user_id,turn_number,status,relationship_id
  ) VALUES(s.id,s.created_by,s.partner_id,p_language_code,'A',s.created_by,1,'waiting',s.relationship_id)
  ON CONFLICT(session_id) DO UPDATE SET
    language_code=COALESCE(public.game_word_sessions.language_code,EXCLUDED.language_code),
    relationship_id=COALESCE(public.game_word_sessions.relationship_id,EXCLUDED.relationship_id),
    updated_at=now();

  RETURN to_jsonb(s);
END;
$$;

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
BEGIN
  SELECT * INTO s FROM public.game_sessions
  WHERE id=p_session_id
    AND (created_by=auth.uid() OR partner_id=auth.uid())
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_SESSION_NOT_FOUND'; END IF;

  SELECT count(*) FILTER (WHERE ready)::integer INTO ready_count
  FROM public.game_players WHERE session_id=p_session_id;
  IF ready_count<2 THEN
    RETURN public.bestie_word_state_v3(p_session_id);
  END IF;

  INSERT INTO public.game_word_sessions(
    session_id,created_by,partner_id,language_code,required_letter,turn_user_id,turn_number,status,turn_started_at,turn_deadline_at,relationship_id
  ) VALUES(
    p_session_id,s.created_by,s.partner_id,p_language_code,'A',s.created_by,1,'playing',now(),now()+interval '90 seconds',s.relationship_id
  )
  ON CONFLICT(session_id) DO UPDATE SET
    language_code=EXCLUDED.language_code,
    status='playing',
    turn_user_id=COALESCE(public.game_word_sessions.turn_user_id,EXCLUDED.turn_user_id),
    turn_started_at=COALESCE(public.game_word_sessions.turn_started_at,now()),
    turn_deadline_at=COALESCE(public.game_word_sessions.turn_deadline_at,now()+interval '90 seconds'),
    updated_at=now();

  UPDATE public.game_sessions
  SET status='playing',updated_at=now()
  WHERE id=p_session_id;

  RETURN public.bestie_word_state_v3(p_session_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_submit_word_game_word_v3(
  p_session_id uuid,
  p_word text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
  w record;
  gp record;
  me uuid:=auth.uid();
  value text:=trim(coalesce(p_word,''));
  norm text;
  required_norm text;
  first_char text;
  last_char text;
  next_user uuid;
  dict_count integer;
  valid_dictionary boolean;
  next_mistakes integer;
  winner uuid;
BEGIN
  SELECT * INTO w FROM public.game_word_sessions
  WHERE session_id=p_session_id
    AND (created_by=me OR partner_id=me)
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WORD_SESSION_NOT_FOUND'; END IF;
  IF w.status='completed' THEN RETURN public.bestie_word_state_v3(p_session_id); END IF;
  IF w.turn_user_id<>me THEN RAISE EXCEPTION 'NOT_YOUR_TURN'; END IF;
  IF value='' THEN RAISE EXCEPTION 'WORD_EMPTY'; END IF;

  norm:=public.bestie_word_normalize_v3(value);
  first_char:=left(norm,1);
  last_char:=right(norm,1);
  required_norm:=public.bestie_word_normalize_v3(w.required_letter);

  SELECT count(*) INTO dict_count
  FROM public.game_word_dictionary d
  WHERE d.language_code=w.language_code AND d.is_active;

  valid_dictionary := CASE WHEN dict_count=0 THEN true ELSE EXISTS(
    SELECT 1 FROM public.game_word_dictionary d
    WHERE d.language_code=w.language_code
      AND d.normalized_word=norm
      AND d.is_active
  ) END;

  IF first_char='' OR first_char<>left(required_norm,1) THEN
    UPDATE public.game_word_sessions
    SET last_error='WORD_MUST_START_WITH_REQUIRED_LETTER',last_error_user_id=me,updated_at=now()
    WHERE session_id=p_session_id;
  ELSIF EXISTS(SELECT 1 FROM public.game_word_plays WHERE session_id=p_session_id AND normalized_word=norm) THEN
    UPDATE public.game_word_sessions
    SET last_error='WORD_ALREADY_USED',last_error_user_id=me,updated_at=now()
    WHERE session_id=p_session_id;
  ELSIF NOT valid_dictionary THEN
    UPDATE public.game_word_sessions
    SET last_error='WORD_NOT_IN_DICTIONARY',last_error_user_id=me,updated_at=now()
    WHERE session_id=p_session_id;
  ELSE
    INSERT INTO public.game_word_plays(
      session_id,user_id,turn_number,word,normalized_word,first_letter,last_letter,points,relationship_id
    ) VALUES(p_session_id,me,w.turn_number,value,norm,first_char,last_char,1,w.relationship_id);

    next_user:=CASE WHEN me=w.created_by THEN w.partner_id ELSE w.created_by END;

    UPDATE public.game_word_sessions
    SET last_word=value,
        required_letter=upper(last_char),
        turn_user_id=next_user,
        turn_number=w.turn_number+1,
        turn_started_at=now(),
        turn_deadline_at=now()+interval '90 seconds',
        last_error=NULL,last_error_user_id=NULL,updated_at=now()
    WHERE session_id=p_session_id;

    RETURN public.bestie_word_state_v3(p_session_id);
  END IF;

  SELECT * INTO gp FROM public.game_players
  WHERE session_id=p_session_id AND user_id=me
  FOR UPDATE;

  next_mistakes:=coalesce(gp.mistakes,0)+1;
  IF next_mistakes>=3 THEN
    winner:=CASE WHEN me=w.created_by THEN w.partner_id ELSE w.created_by END;
    UPDATE public.game_players SET mistakes=next_mistakes,surrendered=(user_id=me) WHERE session_id=p_session_id;
    UPDATE public.game_word_sessions
    SET status='completed',winner_user_id=winner,loser_user_id=me,end_reason='three_mistakes',updated_at=now()
    WHERE session_id=p_session_id;
    UPDATE public.game_sessions SET status='completed',updated_at=now() WHERE id=p_session_id;
  ELSE
    next_user:=CASE WHEN me=w.created_by THEN w.partner_id ELSE w.created_by END;
    UPDATE public.game_players SET mistakes=next_mistakes WHERE session_id=p_session_id AND user_id=me;
    UPDATE public.game_word_sessions
    SET turn_user_id=next_user,
        turn_number=w.turn_number+1,
        turn_started_at=now(),
        turn_deadline_at=now()+interval '90 seconds',
        updated_at=now()
    WHERE session_id=p_session_id;
  END IF;

  RETURN public.bestie_word_state_v3(p_session_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_surrender_word_game_v3(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
  w record;
  me uuid:=auth.uid();
  winner uuid;
BEGIN
  SELECT * INTO w FROM public.game_word_sessions
  WHERE session_id=p_session_id AND (created_by=me OR partner_id=me)
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WORD_SESSION_NOT_FOUND'; END IF;

  winner:=CASE WHEN me=w.created_by THEN w.partner_id ELSE w.created_by END;
  UPDATE public.game_word_sessions
  SET status='completed',winner_user_id=winner,loser_user_id=me,end_reason='surrender',updated_at=now()
  WHERE session_id=p_session_id;
  UPDATE public.game_sessions SET status='completed',updated_at=now() WHERE id=p_session_id;
  RETURN public.bestie_word_state_v3(p_session_id);
END;
$$;

-- ============================================================================
-- TRUTH OR DARE
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.truth_or_dare_prompts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seed_key text,
  mode text NOT NULL CHECK(mode IN ('truth','dare')),
  prompt_tr text NOT NULL DEFAULT '',
  prompt_en text NOT NULL DEFAULT '',
  prompt_de text NOT NULL DEFAULT '',
  prompt_es text NOT NULL DEFAULT '',
  prompt_fr text NOT NULL DEFAULT '',
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.truth_or_dare_prompts
  ADD COLUMN IF NOT EXISTS seed_key text,
  ADD COLUMN IF NOT EXISTS mode text,
  ADD COLUMN IF NOT EXISTS prompt_tr text DEFAULT '',
  ADD COLUMN IF NOT EXISTS prompt_en text DEFAULT '',
  ADD COLUMN IF NOT EXISTS prompt_de text DEFAULT '',
  ADD COLUMN IF NOT EXISTS prompt_es text DEFAULT '',
  ADD COLUMN IF NOT EXISTS prompt_fr text DEFAULT '',
  ADD COLUMN IF NOT EXISTS is_active boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

CREATE UNIQUE INDEX IF NOT EXISTS bestie_truth_dare_seed_uidx
  ON public.truth_or_dare_prompts(seed_key)
  WHERE seed_key IS NOT NULL;

INSERT INTO public.truth_or_dare_prompts
(seed_key,mode,prompt_tr,prompt_en,prompt_de,prompt_es,prompt_fr)
VALUES
('truth_001','truth','Son zamanlarda yaptığın en komik hata neydi?','What is the funniest mistake you made recently?','Was war dein lustigster Fehler in letzter Zeit?','¿Cuál fue el error más gracioso que cometiste recientemente?','Quelle est la chose la plus drôle que tu aies ratée récemment ?'),
('truth_002','truth','Birlikte yaşadığımız hangi anıyı tekrar yaşamak isterdin?','Which memory of us would you relive?','Welche gemeinsame Erinnerung würdest du gern noch einmal erleben?','¿Qué recuerdo nuestro repetirías?','Quel souvenir de nous revivrais-tu ?'),
('truth_003','truth','Benden sakladığın küçük ve zararsız bir şey var mı?','Is there a small harmless thing you have kept from me?','Gibt es eine kleine harmlose Sache, die du mir verschwiegen hast?','¿Hay algo pequeño e inofensivo que me hayas ocultado?','Y a-t-il une petite chose inoffensive que tu m’as cachée ?'),
('truth_004','truth','İlk tanıştığımızda benim hakkımda ne düşünmüştün?','What did you think about me when we first met?','Was hast du gedacht, als wir uns zum ersten Mal trafen?','¿Qué pensaste de mí cuando nos conocimos?','Qu’as-tu pensé de moi lors de notre première rencontre ?'),
('truth_005','truth','Bende en çok sevdiğin özellik hangisi?','What do you like most about me?','Welche Eigenschaft an mir magst du am meisten?','¿Qué es lo que más te gusta de mí?','Qu’est-ce que tu aimes le plus chez moi ?'),
('truth_006','truth','Birlikte yapmak istediğin ama henüz yapmadığımız ne var?','What do you want us to do that we have not done yet?','Was möchtest du mit mir tun, was wir noch nicht gemacht haben?','¿Qué quieres que hagamos que aún no hemos hecho?','Qu’aimerais-tu que nous fassions et que nous n’avons pas encore fait ?'),
('truth_007','truth','Şu anki en büyük hayalin ne?','What is your biggest dream right now?','Was ist gerade dein größter Traum?','¿Cuál es tu mayor sueño ahora mismo?','Quel est ton plus grand rêve en ce moment ?'),
('truth_008','truth','Beni en son ne zaman özledin?','When did you last miss me?','Wann hast du mich zuletzt vermisst?','¿Cuándo fue la última vez que me extrañaste?','Quand est-ce que je t’ai le plus manqué récemment ?'),
('truth_009','truth','Bir ilişkide senin için en önemli şey nedir?','What matters most to you in a relationship?','Was ist dir in einer Beziehung am wichtigsten?','¿Qué es lo más importante para ti en una relación?','Qu’est-ce qui compte le plus pour toi dans une relation ?'),
('truth_010','truth','Benden duymak istediğin bir cümle var mı?','Is there something you want to hear from me?','Gibt es etwas, das du von mir hören möchtest?','¿Hay algo que quieras oír de mí?','Y a-t-il une phrase que tu aimerais entendre de moi ?'),
('dare_001','dare','Partnerine 20 saniye boyunca gözlerinin içine bak ve gülümse.','Look into your partner’s eyes and smile for 20 seconds.','Schau deinem Partner 20 Sekunden in die Augen und lächle.','Mira a tu pareja a los ojos y sonríe durante 20 segundos.','Regarde ton partenaire dans les yeux et souris pendant 20 secondes.'),
('dare_002','dare','Partnerine içten bir iltifat et.','Give your partner a sincere compliment.','Mach deinem Partner ein ehrliches Kompliment.','Hazle un cumplido sincero a tu pareja.','Fais un compliment sincère à ton partenaire.'),
('dare_003','dare','Partnerin için 30 saniyelik komik bir dans yap.','Do a funny 30-second dance for your partner.','Mach 30 Sekunden einen lustigen Tanz für deinen Partner.','Haz un baile divertido de 30 segundos para tu pareja.','Fais une danse amusante de 30 secondes pour ton partenaire.'),
('dare_004','dare','Partnerine gelecekte birlikte yapmak istediğin bir şeyi anlat.','Tell your partner something you want to do together in the future.','Erzähle deinem Partner etwas, das du in Zukunft gemeinsam machen möchtest.','Cuéntale a tu pareja algo que quieras hacer juntos en el futuro.','Raconte à ton partenaire quelque chose que tu veux faire ensemble dans le futur.'),
('dare_005','dare','Partnerine bugün onunla ilgili sevdiğin üç şeyi söyle.','Tell your partner three things you love about them today.','Sag deinem Partner heute drei Dinge, die du an ihm liebst.','Dile a tu pareja tres cosas que te encantan de ella hoy.','Dis à ton partenaire trois choses que tu aimes chez lui/elle aujourd’hui.'),
('dare_006','dare','Partnerine komik bir takma ad bul ve nedenini açıkla.','Give your partner a funny nickname and explain why.','Gib deinem Partner einen lustigen Spitznamen und erkläre warum.','Ponle a tu pareja un apodo divertido y explica por qué.','Donne un surnom drôle à ton partenaire et explique pourquoi.'),
('dare_007','dare','Partnerine sesli bir şekilde kısa bir teşekkür konuşması yap.','Give your partner a short spoken thank-you speech.','Halte für deinen Partner eine kurze Dankesrede.','Hazle a tu pareja un pequeño discurso de agradecimiento.','Fais à ton partenaire un court discours de remerciement.'),
('dare_008','dare','Bir sonraki buluşmanız için küçük bir plan yap.','Make a small plan for your next date.','Plane eine kleine Sache für euer nächstes Date.','Haz un pequeño plan para vuestra próxima cita.','Prépare un petit plan pour votre prochain rendez-vous.'),
('dare_009','dare','Partnerine onunla ilgili en komik anını anlat.','Tell your partner your funniest memory involving them.','Erzähle deinem Partner deine lustigste gemeinsame Erinnerung.','Cuenta tu recuerdo más divertido con tu pareja.','Raconte ton souvenir le plus drôle avec ton partenaire.'),
('dare_010','dare','Partnerine bugün için motive edici bir mesaj söyle.','Give your partner an encouraging message for today.','Sag deinem Partner eine motivierende Nachricht für heute.','Dale a tu pareja un mensaje motivador para hoy.','Donne à ton partenaire un message motivant pour aujourd’hui.')
ON CONFLICT (seed_key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.truth_or_dare_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  partner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'playing',
  current_round integer NOT NULL DEFAULT 1,
  current_mode text,
  current_prompt_id uuid,
  used_prompt_ids uuid[] NOT NULL DEFAULT '{}'::uuid[],
  turn_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  relationship_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.truth_or_dare_sessions
  ADD COLUMN IF NOT EXISTS created_by uuid,
  ADD COLUMN IF NOT EXISTS partner_id uuid,
  ADD COLUMN IF NOT EXISTS status text DEFAULT 'playing',
  ADD COLUMN IF NOT EXISTS current_round integer DEFAULT 1,
  ADD COLUMN IF NOT EXISTS current_mode text,
  ADD COLUMN IF NOT EXISTS current_prompt_id uuid,
  ADD COLUMN IF NOT EXISTS used_prompt_ids uuid[] DEFAULT '{}'::uuid[],
  ADD COLUMN IF NOT EXISTS turn_user_id uuid,
  ADD COLUMN IF NOT EXISTS relationship_id uuid,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

CREATE INDEX IF NOT EXISTS bestie_truth_dare_pair_idx
  ON public.truth_or_dare_sessions(created_by,partner_id,status);
CREATE INDEX IF NOT EXISTS bestie_truth_dare_relationship_idx
  ON public.truth_or_dare_sessions(relationship_id);

DO $$
BEGIN
  IF to_regclass('public.relationship_pairs') IS NOT NULL
     AND to_regclass('public.truth_or_dare_sessions') IS NOT NULL THEN
    UPDATE public.truth_or_dare_sessions t
    SET relationship_id=rp.id
    FROM public.relationship_pairs rp
    WHERE t.relationship_id IS NULL
      AND t.created_by IS NOT NULL
      AND t.partner_id IS NOT NULL
      AND rp.user_a_id=LEAST(t.created_by,t.partner_id)
      AND rp.user_b_id=GREATEST(t.created_by,t.partner_id);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.bestie_truth_dare_state_v3(p_session_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
  SELECT to_jsonb(s) || jsonb_build_object(
    'current_prompt', CASE
      WHEN s.current_prompt_id IS NULL THEN NULL
      ELSE (SELECT to_jsonb(p) FROM public.truth_or_dare_prompts p WHERE p.id=s.current_prompt_id)
    END
  )
  FROM public.truth_or_dare_sessions s
  WHERE s.id=p_session_id
    AND (s.created_by=auth.uid() OR s.partner_id=auth.uid());
$$;

CREATE OR REPLACE FUNCTION public.bestie_create_truth_dare_v3(p_partner_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
  me uuid:=auth.uid();
  s record;
  rel uuid;
BEGIN
  IF me IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF p_partner_id IS NULL OR p_partner_id=me THEN RAISE EXCEPTION 'INVALID_PARTNER'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=me AND paired_with=p_partner_id) THEN
    RAISE EXCEPTION 'NOT_PAIRED';
  END IF;

  SELECT * INTO s FROM public.truth_or_dare_sessions
  WHERE status='playing'
    AND ((created_by=me AND partner_id=p_partner_id)
      OR (created_by=p_partner_id AND partner_id=me))
  ORDER BY created_at DESC LIMIT 1;

  IF NOT FOUND THEN
    rel:=public.bestie_relationship_id_v3(me,p_partner_id);
    INSERT INTO public.truth_or_dare_sessions(
      created_by,partner_id,status,current_round,turn_user_id,relationship_id
    ) VALUES(me,p_partner_id,'playing',1,me,rel)
    RETURNING * INTO s;
  END IF;

  RETURN public.bestie_truth_dare_state_v3(s.id);
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_get_active_truth_dare_v3(p_partner_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
  SELECT public.bestie_truth_dare_state_v3(s.id)
  FROM public.truth_or_dare_sessions s
  WHERE s.status='playing'
    AND ((s.created_by=auth.uid() AND s.partner_id=p_partner_id)
      OR (s.created_by=p_partner_id AND s.partner_id=auth.uid()))
  ORDER BY s.created_at DESC LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.bestie_start_truth_dare_round_v3(
  p_session_id uuid,
  p_mode text,
  p_prompt_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE s record;
BEGIN
  SELECT * INTO s FROM public.truth_or_dare_sessions
  WHERE id=p_session_id AND (created_by=auth.uid() OR partner_id=auth.uid())
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'TRUTH_DARE_SESSION_NOT_FOUND'; END IF;
  IF s.status='completed' THEN RETURN public.bestie_truth_dare_state_v3(p_session_id); END IF;
  IF s.turn_user_id<>auth.uid() THEN RAISE EXCEPTION 'NOT_YOUR_TURN'; END IF;
  IF p_mode NOT IN ('truth','dare') THEN RAISE EXCEPTION 'INVALID_MODE'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.truth_or_dare_prompts
    WHERE id=p_prompt_id AND mode=p_mode AND is_active=true
  ) THEN RAISE EXCEPTION 'PROMPT_NOT_FOUND'; END IF;
  IF p_prompt_id=ANY(COALESCE(s.used_prompt_ids,'{}'::uuid[])) THEN RAISE EXCEPTION 'PROMPT_ALREADY_USED'; END IF;

  UPDATE public.truth_or_dare_sessions
  SET current_mode=p_mode,
      current_prompt_id=p_prompt_id,
      used_prompt_ids=array_append(COALESCE(used_prompt_ids,'{}'::uuid[]),p_prompt_id),
      updated_at=now()
  WHERE id=p_session_id;

  RETURN public.bestie_truth_dare_state_v3(p_session_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_complete_truth_dare_round_v3(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
  s record;
  next_user uuid;
BEGIN
  SELECT * INTO s FROM public.truth_or_dare_sessions
  WHERE id=p_session_id AND (created_by=auth.uid() OR partner_id=auth.uid())
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'TRUTH_DARE_SESSION_NOT_FOUND'; END IF;
  IF s.status='completed' THEN RETURN public.bestie_truth_dare_state_v3(p_session_id); END IF;
  IF s.turn_user_id<>auth.uid() THEN RAISE EXCEPTION 'NOT_YOUR_TURN'; END IF;
  IF s.current_prompt_id IS NULL THEN RAISE EXCEPTION 'NO_ACTIVE_ROUND'; END IF;

  IF s.current_round>=15 THEN
    UPDATE public.truth_or_dare_sessions
    SET status='completed',current_prompt_id=NULL,current_mode=NULL,updated_at=now()
    WHERE id=p_session_id;
  ELSE
    next_user:=CASE WHEN s.turn_user_id=s.created_by THEN s.partner_id ELSE s.created_by END;
    UPDATE public.truth_or_dare_sessions
    SET current_round=s.current_round+1,
        current_prompt_id=NULL,
        current_mode=NULL,
        turn_user_id=next_user,
        updated_at=now()
    WHERE id=p_session_id;
  END IF;

  RETURN public.bestie_truth_dare_state_v3(p_session_id);
END;
$$;

-- ============================================================================
-- MEMORY MATCH
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.memory_match_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  partner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'playing',
  board jsonb NOT NULL DEFAULT '[]'::jsonb,
  flipped_indices jsonb NOT NULL DEFAULT '[]'::jsonb,
  matched_indices jsonb NOT NULL DEFAULT '[]'::jsonb,
  scores jsonb NOT NULL DEFAULT '{}'::jsonb,
  turn_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  relationship_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.memory_match_sessions
  ADD COLUMN IF NOT EXISTS relationship_id uuid,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

CREATE INDEX IF NOT EXISTS bestie_memory_relationship_idx
  ON public.memory_match_sessions(relationship_id);
DO $$
BEGIN
  IF to_regclass('public.relationship_pairs') IS NOT NULL
     AND to_regclass('public.memory_match_sessions') IS NOT NULL THEN
    UPDATE public.memory_match_sessions m
    SET relationship_id=rp.id
    FROM public.relationship_pairs rp
    WHERE m.relationship_id IS NULL
      AND m.created_by IS NOT NULL
      AND m.partner_id IS NOT NULL
      AND rp.user_a_id=LEAST(m.created_by,m.partner_id)
      AND rp.user_b_id=GREATEST(m.created_by,m.partner_id);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.bestie_create_memory_match_v3(p_partner_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
  me uuid:=auth.uid();
  rel uuid;
  s record;
  board jsonb;
  symbols text[]:=ARRAY['🐶','🐱','🦊','🐼','🐸','🦄'];
BEGIN
  IF me IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF p_partner_id IS NULL OR p_partner_id=me THEN RAISE EXCEPTION 'INVALID_PARTNER'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=me AND paired_with=p_partner_id) THEN
    RAISE EXCEPTION 'NOT_PAIRED';
  END IF;

  SELECT * INTO s FROM public.memory_match_sessions
  WHERE status='playing'
    AND ((created_by=me AND partner_id=p_partner_id)
      OR (created_by=p_partner_id AND partner_id=me))
  ORDER BY created_at DESC LIMIT 1;
  IF FOUND THEN RETURN to_jsonb(s); END IF;

  rel:=public.bestie_relationship_id_v3(me,p_partner_id);
  SELECT jsonb_agg(to_jsonb(x)) INTO board
  FROM (SELECT unnest(symbols||symbols) x ORDER BY random()) q;

  INSERT INTO public.memory_match_sessions(
    created_by,partner_id,status,board,flipped_indices,matched_indices,scores,turn_user_id,relationship_id
  ) VALUES(
    me,p_partner_id,'playing',coalesce(board,'[]'::jsonb),'[]'::jsonb,'[]'::jsonb,
    jsonb_build_object(me::text,0,p_partner_id::text,0),me,rel
  ) RETURNING * INTO s;

  RETURN to_jsonb(s);
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_get_active_memory_match_v3(p_partner_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
  SELECT to_jsonb(s)
  FROM public.memory_match_sessions s
  WHERE s.status='playing'
    AND ((s.created_by=auth.uid() AND s.partner_id=p_partner_id)
      OR (s.created_by=p_partner_id AND s.partner_id=auth.uid()))
  ORDER BY s.created_at DESC LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.bestie_memory_flip_v3(p_session_id uuid,p_index integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
  s record;
  flipped integer[];
BEGIN
  SELECT * INTO s FROM public.memory_match_sessions
  WHERE id=p_session_id AND status='playing'
    AND (created_by=auth.uid() OR partner_id=auth.uid())
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'MEMORY_SESSION_NOT_FOUND'; END IF;
  IF s.turn_user_id<>auth.uid() THEN RAISE EXCEPTION 'NOT_YOUR_TURN'; END IF;
  IF p_index<0 OR p_index>=jsonb_array_length(s.board) THEN RAISE EXCEPTION 'INVALID_CARD'; END IF;

  flipped:=coalesce(array(SELECT jsonb_array_elements_text(s.flipped_indices)::integer),'{}'::integer[]);
  IF p_index=ANY(flipped)
     OR p_index=ANY(coalesce(array(SELECT jsonb_array_elements_text(s.matched_indices)::integer),'{}'::integer[]))
     OR coalesce(array_length(flipped,1),0)>=2 THEN
    RAISE EXCEPTION 'CARD_CANNOT_BE_SELECTED';
  END IF;

  UPDATE public.memory_match_sessions
  SET flipped_indices=to_jsonb(array_append(flipped,p_index)),updated_at=now()
  WHERE id=p_session_id;

  RETURN (SELECT to_jsonb(x) FROM public.memory_match_sessions x WHERE x.id=p_session_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_memory_resolve_v3(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
  s record;
  flipped integer[];
  matched integer[];
  board text[];
  a integer;
  b integer;
  same_pair boolean;
  next_user uuid;
  scores jsonb;
BEGIN
  SELECT * INTO s FROM public.memory_match_sessions
  WHERE id=p_session_id AND status='playing'
    AND (created_by=auth.uid() OR partner_id=auth.uid())
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'MEMORY_SESSION_NOT_FOUND'; END IF;
  IF s.turn_user_id<>auth.uid() THEN RAISE EXCEPTION 'NOT_YOUR_TURN'; END IF;

  flipped:=coalesce(array(SELECT jsonb_array_elements_text(s.flipped_indices)::integer),'{}'::integer[]);
  IF coalesce(array_length(flipped,1),0)<>2 THEN RETURN to_jsonb(s); END IF;

  matched:=coalesce(array(SELECT jsonb_array_elements_text(s.matched_indices)::integer),'{}'::integer[]);
  board:=array(SELECT jsonb_array_elements_text(s.board));
  a:=flipped[1]; b:=flipped[2];
  same_pair:=board[a+1]=board[b+1];
  scores:=s.scores;

  IF same_pair THEN
    matched:=array_append(array_append(matched,a),b);
    scores:=jsonb_set(scores,ARRAY[auth.uid()::text],to_jsonb(coalesce((scores->>auth.uid()::text)::integer,0)+1),true);
    next_user:=s.turn_user_id;
  ELSE
    next_user:=CASE WHEN s.turn_user_id=s.created_by THEN s.partner_id ELSE s.created_by END;
  END IF;

  IF coalesce(array_length(matched,1),0)>=array_length(board,1) THEN
    UPDATE public.memory_match_sessions
    SET status='completed',flipped_indices='[]'::jsonb,matched_indices=to_jsonb(matched),scores=scores,updated_at=now()
    WHERE id=p_session_id;
  ELSE
    UPDATE public.memory_match_sessions
    SET flipped_indices='[]'::jsonb,matched_indices=to_jsonb(matched),scores=scores,turn_user_id=next_user,updated_at=now()
    WHERE id=p_session_id;
  END IF;

  RETURN (SELECT to_jsonb(x) FROM public.memory_match_sessions x WHERE x.id=p_session_id);
END;
$$;

-- ============================================================================
-- NAME CITY ANIMAL: REPAIR LIVE TABLE + NEW RPC ENGINE
-- ============================================================================

ALTER TABLE IF EXISTS public.name_city_animal_games
  ADD COLUMN IF NOT EXISTS session_id uuid,
  ADD COLUMN IF NOT EXISTS created_by uuid,
  ADD COLUMN IF NOT EXISTS partner_id uuid,
  ADD COLUMN IF NOT EXISTS language_code text DEFAULT 'en',
  ADD COLUMN IF NOT EXISTS current_letter text DEFAULT 'A',
  ADD COLUMN IF NOT EXISTS round_number integer DEFAULT 1,
  ADD COLUMN IF NOT EXISTS total_rounds integer DEFAULT 5,
  ADD COLUMN IF NOT EXISTS status text DEFAULT 'waiting',
  ADD COLUMN IF NOT EXISTS round_deadline_at timestamptz,
  ADD COLUMN IF NOT EXISTS winner_user_id uuid,
  ADD COLUMN IF NOT EXISTS created_ready boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS partner_ready boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS created_score integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS partner_score integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_round_results jsonb DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS relationship_id uuid,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

DO $$
BEGIN
  UPDATE public.name_city_animal_games
  SET session_id=gen_random_uuid()
  WHERE session_id IS NULL;
END $$;

ALTER TABLE IF EXISTS public.name_city_animal_answers
  ADD COLUMN IF NOT EXISTS session_id uuid,
  ADD COLUMN IF NOT EXISTS round_number integer DEFAULT 1,
  ADD COLUMN IF NOT EXISTS user_id uuid,
  ADD COLUMN IF NOT EXISTS name text DEFAULT '',
  ADD COLUMN IF NOT EXISTS city text DEFAULT '',
  ADD COLUMN IF NOT EXISTS animal text DEFAULT '',
  ADD COLUMN IF NOT EXISTS plant text DEFAULT '',
  ADD COLUMN IF NOT EXISTS thing text DEFAULT '',
  ADD COLUMN IF NOT EXISTS country text DEFAULT '',
  ADD COLUMN IF NOT EXISTS name_normalized text DEFAULT '',
  ADD COLUMN IF NOT EXISTS city_normalized text DEFAULT '',
  ADD COLUMN IF NOT EXISTS animal_normalized text DEFAULT '',
  ADD COLUMN IF NOT EXISTS plant_normalized text DEFAULT '',
  ADD COLUMN IF NOT EXISTS thing_normalized text DEFAULT '',
  ADD COLUMN IF NOT EXISTS country_normalized text DEFAULT '',
  ADD COLUMN IF NOT EXISTS name_valid boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS city_valid boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS animal_valid boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS plant_valid boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS thing_valid boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS country_valid boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS points integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS submitted_at timestamptz DEFAULT now();

CREATE INDEX IF NOT EXISTS bestie_nca_session_round_idx
  ON public.name_city_animal_answers(session_id,round_number);
CREATE INDEX IF NOT EXISTS bestie_nca_pair_idx
  ON public.name_city_animal_games(created_by,partner_id,status);
CREATE INDEX IF NOT EXISTS bestie_nca_relationship_idx
  ON public.name_city_animal_games(relationship_id);

DO $$
BEGIN
  IF to_regclass('public.relationship_pairs') IS NOT NULL THEN
    UPDATE public.name_city_animal_games g
    SET relationship_id=rp.id
    FROM public.relationship_pairs rp
    WHERE g.relationship_id IS NULL
      AND g.created_by IS NOT NULL
      AND g.partner_id IS NOT NULL
      AND rp.user_a_id=LEAST(g.created_by,g.partner_id)
      AND rp.user_b_id=GREATEST(g.created_by,g.partner_id);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.bestie_nca_normalize_v3(input_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT translate(lower(trim(coalesce(input_text,''))),
    'ıİğĞüÜşŞöÖçÇâÂîÎûÛáÁéÉíÍóÓúÚäÄëËïÏñÑ',
    'iIgGuUsSoOcCaAiIuUaAeEiIoOuUaAeEiInN');
$$;

CREATE OR REPLACE FUNCTION public.bestie_nca_pick_letter_v3(p_language_code text)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
  letters text[];
  chosen text;
BEGIN
  letters:=CASE p_language_code
    WHEN 'tr' THEN ARRAY['A','B','C','Ç','D','E','F','G','H','İ','K','L','M','N','O','Ö','P','R','S','Ş','T','U','Ü','Y']
    WHEN 'de' THEN ARRAY['A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','R','S','T','U','V','W','Z']
    WHEN 'es' THEN ARRAY['A','B','C','D','E','F','G','H','I','J','L','M','N','O','P','R','S','T','U','V','Y','Z']
    WHEN 'fr' THEN ARRAY['A','B','C','D','E','F','G','H','I','J','L','M','N','O','P','R','S','T','V','Y','Z']
    ELSE ARRAY['A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','R','S','T','U','V','Y','Z']
  END;

  SELECT x INTO chosen
  FROM unnest(letters) x
  WHERE EXISTS(SELECT 1 FROM public.name_city_animal_dictionary d WHERE d.language_code=p_language_code AND d.category='name' AND d.is_active AND left(d.normalized_word,1)=left(public.bestie_nca_normalize_v3(x),1))
    AND EXISTS(SELECT 1 FROM public.name_city_animal_dictionary d WHERE d.language_code=p_language_code AND d.category='city' AND d.is_active AND left(d.normalized_word,1)=left(public.bestie_nca_normalize_v3(x),1))
    AND EXISTS(SELECT 1 FROM public.name_city_animal_dictionary d WHERE d.language_code=p_language_code AND d.category='animal' AND d.is_active AND left(d.normalized_word,1)=left(public.bestie_nca_normalize_v3(x),1))
    AND EXISTS(SELECT 1 FROM public.name_city_animal_dictionary d WHERE d.language_code=p_language_code AND d.category='plant' AND d.is_active AND left(d.normalized_word,1)=left(public.bestie_nca_normalize_v3(x),1))
    AND EXISTS(SELECT 1 FROM public.name_city_animal_dictionary d WHERE d.language_code=p_language_code AND d.category='thing' AND d.is_active AND left(d.normalized_word,1)=left(public.bestie_nca_normalize_v3(x),1))
    AND EXISTS(SELECT 1 FROM public.name_city_animal_dictionary d WHERE d.language_code=p_language_code AND d.category='country' AND d.is_active AND left(d.normalized_word,1)=left(public.bestie_nca_normalize_v3(x),1))
  ORDER BY random() LIMIT 1;

  IF chosen IS NULL THEN
    SELECT x INTO chosen FROM unnest(letters) x ORDER BY random() LIMIT 1;
  END IF;
  RETURN chosen;
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_nca_state_v3(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
  g record;
  me uuid:=auth.uid();
  created_submitted boolean;
  partner_submitted boolean;
  current_results jsonb;
BEGIN
  SELECT * INTO g FROM public.name_city_animal_games
  WHERE session_id=p_session_id
    AND (created_by=me OR partner_id=me);
  IF NOT FOUND THEN RAISE EXCEPTION 'NCA_SESSION_NOT_FOUND'; END IF;

  SELECT EXISTS(SELECT 1 FROM public.name_city_animal_answers a WHERE a.session_id=g.session_id AND a.round_number=g.round_number AND a.user_id=g.created_by)
  INTO created_submitted;
  SELECT EXISTS(SELECT 1 FROM public.name_city_animal_answers a WHERE a.session_id=g.session_id AND a.round_number=g.round_number AND a.user_id=g.partner_id)
  INTO partner_submitted;

  SELECT jsonb_agg(jsonb_build_object(
    'user_id',a.user_id,'name',a.name,'city',a.city,'animal',a.animal,'plant',a.plant,'thing',a.thing,'country',a.country,
    'name_valid',a.name_valid,'city_valid',a.city_valid,'animal_valid',a.animal_valid,'plant_valid',a.plant_valid,
    'thing_valid',a.thing_valid,'country_valid',a.country_valid,'points',a.points
  ) ORDER BY a.submitted_at)
  INTO current_results
  FROM public.name_city_animal_answers a
  WHERE a.session_id=g.session_id AND a.round_number=g.round_number;

  RETURN jsonb_build_object(
    'session_id',g.session_id,'created_by',g.created_by,'partner_id',g.partner_id,'language_code',g.language_code,
    'current_letter',g.current_letter,'round_number',g.round_number,'total_rounds',g.total_rounds,'status',g.status,
    'round_deadline_at',g.round_deadline_at,'winner_user_id',g.winner_user_id,'created_ready',g.created_ready,
    'partner_ready',g.partner_ready,'created_score',g.created_score,'partner_score',g.partner_score,
    'created_submitted',created_submitted,'partner_submitted',partner_submitted,
    'round_results',CASE WHEN current_results IS NOT NULL THEN current_results ELSE COALESCE(g.last_round_results,'[]'::jsonb) END
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_create_nca_v3(p_language_code text,p_partner_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
  me uuid:=auth.uid();
  g record;
  rel uuid;
BEGIN
  IF me IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF p_language_code NOT IN ('tr','en','de','es','fr') THEN RAISE EXCEPTION 'UNSUPPORTED_LANGUAGE'; END IF;
  IF p_partner_id IS NULL OR p_partner_id=me THEN RAISE EXCEPTION 'INVALID_PARTNER'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=me AND paired_with=p_partner_id) THEN RAISE EXCEPTION 'NOT_PAIRED'; END IF;

  SELECT * INTO g FROM public.name_city_animal_games
  WHERE status IN ('waiting','playing')
    AND ((created_by=me AND partner_id=p_partner_id)
      OR (created_by=p_partner_id AND partner_id=me))
  ORDER BY created_at DESC LIMIT 1;

  IF FOUND THEN RETURN public.bestie_nca_state_v3(g.session_id); END IF;

  rel:=public.bestie_relationship_id_v3(me,p_partner_id);
  INSERT INTO public.name_city_animal_games(
    session_id,created_by,partner_id,language_code,current_letter,round_number,total_rounds,status,
    created_ready,partner_ready,created_score,partner_score,last_round_results,relationship_id
  ) VALUES(
    gen_random_uuid(),me,p_partner_id,p_language_code,'A',1,5,'waiting',false,false,0,0,'[]'::jsonb,rel
  ) RETURNING * INTO g;

  UPDATE public.name_city_animal_games
  SET current_letter=public.bestie_nca_pick_letter_v3(p_language_code),updated_at=now()
  WHERE session_id=g.session_id;

  RETURN public.bestie_nca_state_v3(g.session_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_nca_ready_v3(p_ready boolean,p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
  g record;
  me uuid:=auth.uid();
BEGIN
  SELECT * INTO g FROM public.name_city_animal_games
  WHERE session_id=p_session_id AND (created_by=me OR partner_id=me)
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'NCA_SESSION_NOT_FOUND'; END IF;
  IF g.status<>'waiting' THEN RETURN public.bestie_nca_state_v3(p_session_id); END IF;

  IF me=g.created_by THEN
    UPDATE public.name_city_animal_games SET created_ready=p_ready,updated_at=now() WHERE session_id=p_session_id;
  ELSE
    UPDATE public.name_city_animal_games SET partner_ready=p_ready,updated_at=now() WHERE session_id=p_session_id;
  END IF;
  RETURN public.bestie_nca_state_v3(p_session_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_start_nca_v3(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE g record; l text;
BEGIN
  SELECT * INTO g FROM public.name_city_animal_games
  WHERE session_id=p_session_id AND (created_by=auth.uid() OR partner_id=auth.uid())
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'NCA_SESSION_NOT_FOUND'; END IF;
  IF g.status='completed' OR g.status='playing' THEN RETURN public.bestie_nca_state_v3(p_session_id); END IF;
  IF NOT(g.created_ready AND g.partner_ready) THEN RETURN public.bestie_nca_state_v3(p_session_id); END IF;

  l:=public.bestie_nca_pick_letter_v3(g.language_code);
  UPDATE public.name_city_animal_games
  SET status='playing',current_letter=l,round_number=1,round_deadline_at=now()+interval '45 seconds',updated_at=now()
  WHERE session_id=p_session_id;
  RETURN public.bestie_nca_state_v3(p_session_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_nca_validate_v3(
  p_language text,p_category text,p_word text,p_letter text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
  SELECT public.bestie_nca_normalize_v3(p_word)<>''
     AND left(public.bestie_nca_normalize_v3(p_word),1)=left(public.bestie_nca_normalize_v3(p_letter),1)
     AND EXISTS(
       SELECT 1 FROM public.name_city_animal_dictionary d
       WHERE d.language_code=p_language
         AND d.category=p_category
         AND d.normalized_word=public.bestie_nca_normalize_v3(p_word)
         AND d.is_active
     );
$$;

CREATE OR REPLACE FUNCTION public.bestie_resolve_nca_v3(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
  g record;
  a record;
  other_a record;
  my_points integer;
  other_points integer;
  new_created integer;
  new_partner integer;
  results jsonb;
  new_letter text;
BEGIN
  SELECT * INTO g FROM public.name_city_animal_games
  WHERE session_id=p_session_id
    AND (created_by=auth.uid() OR partner_id=auth.uid())
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'NCA_SESSION_NOT_FOUND'; END IF;

  FOR a IN SELECT * FROM public.name_city_animal_answers
  WHERE session_id=g.session_id AND round_number=g.round_number
  LOOP
    UPDATE public.name_city_animal_answers x SET
      name_valid=public.bestie_nca_validate_v3(g.language_code,'name',a.name,g.current_letter),
      city_valid=public.bestie_nca_validate_v3(g.language_code,'city',a.city,g.current_letter),
      animal_valid=public.bestie_nca_validate_v3(g.language_code,'animal',a.animal,g.current_letter),
      plant_valid=public.bestie_nca_validate_v3(g.language_code,'plant',a.plant,g.current_letter),
      thing_valid=public.bestie_nca_validate_v3(g.language_code,'thing',a.thing,g.current_letter),
      country_valid=public.bestie_nca_validate_v3(g.language_code,'country',a.country,g.current_letter)
    WHERE x.id=a.id;
  END LOOP;

  -- Scoring: unique valid answer = 2, same valid answer by both = 1 each.
  UPDATE public.name_city_animal_answers a
  SET points=(CASE WHEN name_valid THEN 2 ELSE 0 END)+
             (CASE WHEN city_valid THEN 2 ELSE 0 END)+
             (CASE WHEN animal_valid THEN 2 ELSE 0 END)+
             (CASE WHEN plant_valid THEN 2 ELSE 0 END)+
             (CASE WHEN thing_valid THEN 2 ELSE 0 END)+
             (CASE WHEN country_valid THEN 2 ELSE 0 END)
  WHERE session_id=g.session_id AND round_number=g.round_number;

  SELECT * INTO a FROM public.name_city_animal_answers
  WHERE session_id=g.session_id AND round_number=g.round_number AND user_id=g.created_by;
  SELECT * INTO other_a FROM public.name_city_animal_answers
  WHERE session_id=g.session_id AND round_number=g.round_number AND user_id=g.partner_id;

  IF a.id IS NOT NULL AND other_a.id IS NOT NULL THEN
    IF a.name_valid AND other_a.name_valid AND public.bestie_nca_normalize_v3(a.name)=public.bestie_nca_normalize_v3(other_a.name) THEN
      UPDATE public.name_city_animal_answers SET points=points-1 WHERE id IN (a.id,other_a.id);
    END IF;
    IF a.city_valid AND other_a.city_valid AND public.bestie_nca_normalize_v3(a.city)=public.bestie_nca_normalize_v3(other_a.city) THEN
      UPDATE public.name_city_animal_answers SET points=points-1 WHERE id IN (a.id,other_a.id);
    END IF;
    IF a.animal_valid AND other_a.animal_valid AND public.bestie_nca_normalize_v3(a.animal)=public.bestie_nca_normalize_v3(other_a.animal) THEN
      UPDATE public.name_city_animal_answers SET points=points-1 WHERE id IN (a.id,other_a.id);
    END IF;
    IF a.plant_valid AND other_a.plant_valid AND public.bestie_nca_normalize_v3(a.plant)=public.bestie_nca_normalize_v3(other_a.plant) THEN
      UPDATE public.name_city_animal_answers SET points=points-1 WHERE id IN (a.id,other_a.id);
    END IF;
    IF a.thing_valid AND other_a.thing_valid AND public.bestie_nca_normalize_v3(a.thing)=public.bestie_nca_normalize_v3(other_a.thing) THEN
      UPDATE public.name_city_animal_answers SET points=points-1 WHERE id IN (a.id,other_a.id);
    END IF;
    IF a.country_valid AND other_a.country_valid AND public.bestie_nca_normalize_v3(a.country)=public.bestie_nca_normalize_v3(other_a.country) THEN
      UPDATE public.name_city_animal_answers SET points=points-1 WHERE id IN (a.id,other_a.id);
    END IF;
  END IF;

  SELECT COALESCE(points,0) INTO my_points FROM public.name_city_animal_answers
  WHERE session_id=g.session_id AND round_number=g.round_number AND user_id=g.created_by;
  SELECT COALESCE(points,0) INTO other_points FROM public.name_city_animal_answers
  WHERE session_id=g.session_id AND round_number=g.round_number AND user_id=g.partner_id;

  new_created:=g.created_score+COALESCE(my_points,0);
  new_partner:=g.partner_score+COALESCE(other_points,0);

  SELECT jsonb_agg(jsonb_build_object(
    'user_id',user_id,'name',name,'city',city,'animal',animal,'plant',plant,'thing',thing,'country',country,
    'name_valid',name_valid,'city_valid',city_valid,'animal_valid',animal_valid,'plant_valid',plant_valid,
    'thing_valid',thing_valid,'country_valid',country_valid,'points',points
  ) ORDER BY submitted_at)
  INTO results
  FROM public.name_city_animal_answers
  WHERE session_id=g.session_id AND round_number=g.round_number;

  IF g.round_number>=g.total_rounds THEN
    UPDATE public.name_city_animal_games
    SET created_score=new_created,partner_score=new_partner,status='completed',winner_user_id=
      CASE WHEN new_created>new_partner THEN created_by WHEN new_partner>new_created THEN partner_id ELSE NULL END,
      round_deadline_at=NULL,last_round_results=COALESCE(results,'[]'::jsonb),updated_at=now()
    WHERE session_id=p_session_id;
  ELSE
    new_letter:=public.bestie_nca_pick_letter_v3(g.language_code);
    UPDATE public.name_city_animal_games
    SET created_score=new_created,partner_score=new_partner,round_number=g.round_number+1,current_letter=new_letter,
        round_deadline_at=now()+interval '45 seconds',last_round_results=COALESCE(results,'[]'::jsonb),updated_at=now()
    WHERE session_id=p_session_id;
  END IF;

  RETURN public.bestie_nca_state_v3(p_session_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_expire_nca_v3(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE g record;
BEGIN
  SELECT * INTO g FROM public.name_city_animal_games
  WHERE session_id=p_session_id AND (created_by=auth.uid() OR partner_id=auth.uid())
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'NCA_SESSION_NOT_FOUND'; END IF;
  IF g.status<>'playing' THEN RETURN public.bestie_nca_state_v3(p_session_id); END IF;
  IF now()<COALESCE(g.round_deadline_at,now()) THEN RETURN public.bestie_nca_state_v3(p_session_id); END IF;

  INSERT INTO public.name_city_animal_answers(session_id,round_number,user_id)
  SELECT p_session_id,g.round_number,g.created_by
  WHERE NOT EXISTS(SELECT 1 FROM public.name_city_animal_answers WHERE session_id=p_session_id AND round_number=g.round_number AND user_id=g.created_by);
  INSERT INTO public.name_city_animal_answers(session_id,round_number,user_id)
  SELECT p_session_id,g.round_number,g.partner_id
  WHERE NOT EXISTS(SELECT 1 FROM public.name_city_animal_answers WHERE session_id=p_session_id AND round_number=g.round_number AND user_id=g.partner_id);

  RETURN public.bestie_resolve_nca_v3(p_session_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_submit_nca_v3(
  p_session_id uuid,p_name text,p_city text,p_animal text,p_plant text,p_thing text,p_country text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
  g record;
  me uuid:=auth.uid();
  answer_count integer;
BEGIN
  SELECT * INTO g FROM public.name_city_animal_games
  WHERE session_id=p_session_id AND (created_by=me OR partner_id=me)
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'NCA_SESSION_NOT_FOUND'; END IF;
  IF g.status<>'playing' THEN RETURN public.bestie_nca_state_v3(p_session_id); END IF;
  IF now()>COALESCE(g.round_deadline_at,now()) THEN RETURN public.bestie_expire_nca_v3(p_session_id); END IF;
  IF EXISTS(SELECT 1 FROM public.name_city_animal_answers WHERE session_id=p_session_id AND round_number=g.round_number AND user_id=me) THEN
    RETURN public.bestie_nca_state_v3(p_session_id);
  END IF;

  INSERT INTO public.name_city_animal_answers(
    session_id,round_number,user_id,name,city,animal,plant,thing,country,
    name_normalized,city_normalized,animal_normalized,plant_normalized,thing_normalized,country_normalized
  ) VALUES(
    p_session_id,g.round_number,me,trim(coalesce(p_name,'')),trim(coalesce(p_city,'')),trim(coalesce(p_animal,'')),
    trim(coalesce(p_plant,'')),trim(coalesce(p_thing,'')),trim(coalesce(p_country,'')),
    public.bestie_nca_normalize_v3(p_name),public.bestie_nca_normalize_v3(p_city),public.bestie_nca_normalize_v3(p_animal),
    public.bestie_nca_normalize_v3(p_plant),public.bestie_nca_normalize_v3(p_thing),public.bestie_nca_normalize_v3(p_country)
  );

  SELECT count(*) INTO answer_count FROM public.name_city_animal_answers
  WHERE session_id=p_session_id AND round_number=g.round_number;
  IF answer_count>=2 THEN RETURN public.bestie_resolve_nca_v3(p_session_id); END IF;
  RETURN public.bestie_nca_state_v3(p_session_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.bestie_surrender_nca_v3(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.name_city_animal_games WHERE session_id=p_session_id AND (created_by=auth.uid() OR partner_id=auth.uid())) THEN
    RAISE EXCEPTION 'NCA_SESSION_NOT_FOUND';
  END IF;
  UPDATE public.name_city_animal_games
  SET status='completed',round_deadline_at=NULL,updated_at=now(),
      winner_user_id=CASE WHEN created_by=auth.uid() THEN partner_id ELSE created_by END
  WHERE session_id=p_session_id;
  RETURN public.bestie_nca_state_v3(p_session_id);
END;
$$;

-- ============================================================================
-- RLS / REALTIME FOR NEW ROOT TABLES
-- ============================================================================

ALTER TABLE public.game_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.game_players ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.game_rounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.game_answers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.game_word_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.game_word_plays ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.truth_or_dare_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.truth_or_dare_prompts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.memory_match_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS bestie_game_sessions_select_v3 ON public.game_sessions;
CREATE POLICY bestie_game_sessions_select_v3 ON public.game_sessions
FOR SELECT TO authenticated
USING(auth.uid()=created_by OR auth.uid()=partner_id);

DROP POLICY IF EXISTS bestie_game_players_select_v3 ON public.game_players;
CREATE POLICY bestie_game_players_select_v3 ON public.game_players
FOR SELECT TO authenticated
USING(EXISTS(SELECT 1 FROM public.game_sessions gs WHERE gs.id=game_players.session_id AND (gs.created_by=auth.uid() OR gs.partner_id=auth.uid())));

DROP POLICY IF EXISTS bestie_game_rounds_select_v3 ON public.game_rounds;
CREATE POLICY bestie_game_rounds_select_v3 ON public.game_rounds
FOR SELECT TO authenticated
USING(EXISTS(SELECT 1 FROM public.game_sessions gs WHERE gs.id=game_rounds.session_id AND (gs.created_by=auth.uid() OR gs.partner_id=auth.uid())));

DROP POLICY IF EXISTS bestie_game_answers_select_v3 ON public.game_answers;
CREATE POLICY bestie_game_answers_select_v3 ON public.game_answers
FOR SELECT TO authenticated
USING(EXISTS(
  SELECT 1 FROM public.game_rounds gr
  JOIN public.game_sessions gs ON gs.id=gr.session_id
  WHERE gr.id=game_answers.round_id AND (gs.created_by=auth.uid() OR gs.partner_id=auth.uid())
));

DROP POLICY IF EXISTS bestie_word_sessions_select_v3 ON public.game_word_sessions;
CREATE POLICY bestie_word_sessions_select_v3 ON public.game_word_sessions
FOR SELECT TO authenticated
USING(auth.uid()=created_by OR auth.uid()=partner_id);

DROP POLICY IF EXISTS bestie_word_plays_select_v3 ON public.game_word_plays;
CREATE POLICY bestie_word_plays_select_v3 ON public.game_word_plays
FOR SELECT TO authenticated
USING(EXISTS(
  SELECT 1 FROM public.game_word_sessions w
  WHERE w.session_id=game_word_plays.session_id AND (w.created_by=auth.uid() OR w.partner_id=auth.uid())
));

DROP POLICY IF EXISTS bestie_truth_dare_sessions_select_v3 ON public.truth_or_dare_sessions;
CREATE POLICY bestie_truth_dare_sessions_select_v3 ON public.truth_or_dare_sessions
FOR SELECT TO authenticated
USING(auth.uid()=created_by OR auth.uid()=partner_id);

DROP POLICY IF EXISTS bestie_truth_dare_prompts_select_v3 ON public.truth_or_dare_prompts;
CREATE POLICY bestie_truth_dare_prompts_select_v3 ON public.truth_or_dare_prompts
FOR SELECT TO authenticated
USING(is_active=true);

DROP POLICY IF EXISTS bestie_memory_match_select_v3 ON public.memory_match_sessions;
CREATE POLICY bestie_memory_match_select_v3 ON public.memory_match_sessions
FOR SELECT TO authenticated
USING(auth.uid()=created_by OR auth.uid()=partner_id);

-- Realtime publication: duplicate_object is harmless when already enabled.
DO $$
BEGIN
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.game_sessions; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.game_players; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.game_rounds; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.game_answers; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.game_word_sessions; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.game_word_plays; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.truth_or_dare_sessions; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.memory_match_sessions; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.name_city_animal_games; EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;

-- ============================================================================
-- GRANTS (ALL V3 FUNCTIONS ARE DEFINED BEFORE THIS POINT)
-- ============================================================================

GRANT EXECUTE ON FUNCTION public.bestie_game_get_session_v3(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_game_get_players_v3(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_game_get_answers_v3(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_game_pick_question_v3(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_create_or_join_game_session_v3(text,uuid,text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_get_active_game_session_v3(text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_set_game_ready_v3(uuid,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_start_game_if_ready_v3(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_submit_game_answer_v3(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_resolve_game_round_v3(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_get_game_round_results_v3(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_advance_game_round_v3(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_count_unseen_game_questions_for_pair_v3(text,uuid,text[]) TO authenticated;

GRANT EXECUTE ON FUNCTION public.bestie_word_normalize_v3(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_word_state_v3(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_word_get_plays_v3(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_create_or_join_word_game_session_v3(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_start_word_game_v3(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_submit_word_game_word_v3(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_surrender_word_game_v3(uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.bestie_truth_dare_state_v3(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_create_truth_dare_v3(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_get_active_truth_dare_v3(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_start_truth_dare_round_v3(uuid,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_complete_truth_dare_round_v3(uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.bestie_create_memory_match_v3(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_get_active_memory_match_v3(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_memory_flip_v3(uuid,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_memory_resolve_v3(uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.bestie_nca_normalize_v3(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_nca_pick_letter_v3(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_nca_state_v3(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_create_nca_v3(text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_nca_ready_v3(boolean,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_start_nca_v3(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_nca_validate_v3(text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_resolve_nca_v3(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_expire_nca_v3(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_submit_nca_v3(uuid,text,text,text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bestie_surrender_nca_v3(uuid) TO authenticated;

NOTIFY pgrst,'reload schema';

COMMIT;
