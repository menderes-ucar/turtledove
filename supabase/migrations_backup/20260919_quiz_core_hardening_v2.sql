-- KPSS Kolay - Quiz Core Hardening V2
-- Applies on top of 20260918_quiz_core_hardening.sql.
-- Fixes: client question retrieval, explanation exposure, duplicate answers,
-- and completion after timer expiry.

BEGIN;

-- Client must never read the answer key or explanation directly from questions.
DROP VIEW IF EXISTS public.public_questions;
CREATE VIEW public.public_questions
WITH (security_invoker = true)
AS
SELECT
  id,
  subject_id,
  question_text,
  image_url,
  option_a,
  option_b,
  option_c,
  option_d,
  option_e,
  difficulty_level,
  source,
  year
FROM public.questions
WHERE is_deleted = FALSE;

-- The view is intentionally not the primary quiz transport. Quiz questions are
-- returned only for questions belonging to the authenticated user's session.
REVOKE ALL ON public.questions FROM anon, authenticated;
REVOKE ALL ON public.public_questions FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_quiz_questions(p_session_id UUID)
RETURNS TABLE (
  id UUID,
  subject_id UUID,
  question_text TEXT,
  image_url TEXT,
  option_a TEXT,
  option_b TEXT,
  option_c TEXT,
  option_d TEXT,
  option_e TEXT,
  difficulty_level INTEGER,
  source TEXT,
  year INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_session public.quiz_sessions%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  SELECT * INTO v_session
  FROM public.quiz_sessions
  WHERE id = p_session_id AND user_id = v_user_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'SESSION_NOT_FOUND'; END IF;

  RETURN QUERY
  SELECT
    q.id, q.subject_id, q.question_text, q.image_url,
    q.option_a, q.option_b, q.option_c, q.option_d, q.option_e,
    q.difficulty_level, q.source, q.year
  FROM public.questions q
  WHERE q.is_deleted = FALSE
    AND q.id = ANY(v_session.question_ids)
  ORDER BY array_position(v_session.question_ids, q.id);
END;
$$;

REVOKE ALL ON FUNCTION public.get_quiz_questions(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_quiz_questions(UUID) TO authenticated;

-- A question can be answered only once in a session.
-- This replaces an accidental duplicate insert with an explicit error.
CREATE OR REPLACE FUNCTION public.submit_quiz_answer(
  p_session_id UUID,
  p_question_id UUID,
  p_selected_option TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_session public.quiz_sessions%ROWTYPE;
  v_correct_option CHAR(1);
  v_explanation TEXT;
  v_is_correct BOOLEAN;
  v_answer_id UUID;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF upper(trim(coalesce(p_selected_option,''))) NOT IN ('A','B','C','D','E') THEN
    RAISE EXCEPTION 'INVALID_OPTION';
  END IF;

  SELECT * INTO v_session
  FROM public.quiz_sessions
  WHERE id = p_session_id AND user_id = v_user_id AND status = 'active'
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'SESSION_NOT_FOUND'; END IF;

  IF NOT (p_question_id = ANY(v_session.question_ids)) THEN
    RAISE EXCEPTION 'QUESTION_NOT_IN_SESSION';
  END IF;

  IF v_session.is_timed
     AND NOW() > v_session.started_at + (v_session.time_limit_seconds * INTERVAL '1 second') THEN
    RAISE EXCEPTION 'QUIZ_TIME_EXPIRED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.quiz_answers
    WHERE session_id = v_session.id AND question_id = p_question_id
  ) THEN
    RAISE EXCEPTION 'QUESTION_ALREADY_ANSWERED';
  END IF;

  SELECT correct_option, explanation
  INTO v_correct_option, v_explanation
  FROM public.questions
  WHERE id = p_question_id AND is_deleted = FALSE;
  IF NOT FOUND THEN RAISE EXCEPTION 'QUESTION_NOT_FOUND'; END IF;

  v_is_correct := upper(trim(p_selected_option)) = v_correct_option;

  INSERT INTO public.quiz_answers(
    session_id, user_id, question_id, selected_option, is_correct
  ) VALUES (
    p_session_id, v_user_id, p_question_id,
    upper(trim(p_selected_option))::CHAR(1), v_is_correct
  ) RETURNING id INTO v_answer_id;

  IF NOT v_is_correct THEN
    INSERT INTO public.error_notebook(
      user_id, question_id, subject_id, subject_name, question_text,
      user_selected_option, correct_option, is_resolved, wrong_count,
      last_wrong_at, user_note
    )
    SELECT
      v_user_id, q.id, q.subject_id, s.name, q.question_text,
      upper(trim(p_selected_option))::CHAR(1), v_correct_option, FALSE, 1,
      NOW(), NULL
    FROM public.questions q
    JOIN public.subjects s ON s.id = q.subject_id
    WHERE q.id = p_question_id
    ON CONFLICT (user_id, question_id) DO UPDATE
      SET wrong_count = public.error_notebook.wrong_count + 1,
          last_wrong_at = NOW(),
          user_selected_option = EXCLUDED.user_selected_option,
          correct_option = EXCLUDED.correct_option,
          is_resolved = FALSE,
          updated_at = NOW();
  END IF;

  RETURN jsonb_build_object(
    'answer_id', v_answer_id,
    'is_correct', v_is_correct,
    'correct_option', v_correct_option,
    'explanation', COALESCE(v_explanation, '')
  );
END;
$$;

-- Completing an expired timed quiz is valid: unanswered questions become blank.
CREATE OR REPLACE FUNCTION public.complete_quiz_session(p_session_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_session public.quiz_sessions%ROWTYPE;
  v_answered INTEGER;
  v_correct INTEGER;
  v_wrong INTEGER;
  v_blank INTEGER;
  v_duration INTEGER;
  v_attempt_id UUID;
  v_net NUMERIC(8,2);
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  SELECT * INTO v_session
  FROM public.quiz_sessions
  WHERE id = p_session_id AND user_id = v_user_id AND status = 'active'
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'SESSION_NOT_FOUND'; END IF;

  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE is_correct),
    COUNT(*) FILTER (WHERE NOT is_correct)
  INTO v_answered, v_correct, v_wrong
  FROM public.quiz_answers
  WHERE session_id = v_session.id AND user_id = v_user_id;

  v_blank := GREATEST(0, v_session.total_questions - v_answered);
  v_duration := GREATEST(0, EXTRACT(EPOCH FROM (NOW() - v_session.started_at))::INTEGER);
  IF v_session.is_timed THEN
    v_duration := LEAST(v_duration, v_session.time_limit_seconds);
  END IF;
  v_net := v_correct - (v_wrong::NUMERIC / 4.0);

  UPDATE public.quiz_sessions
  SET status = 'completed', completed_at = NOW()
  WHERE id = v_session.id;

  INSERT INTO public.user_quiz_attempts(
    user_id, subject_id, status, total_questions,
    correct_answers, wrong_answers, blank_answers,
    duration_seconds, score, is_timed, time_limit_seconds,
    started_at, completed_at
  ) VALUES (
    v_user_id, v_session.subject_id, 'completed', v_session.total_questions,
    v_correct, v_wrong, v_blank, v_duration, v_net,
    v_session.is_timed, v_session.time_limit_seconds,
    v_session.started_at, NOW()
  ) RETURNING id INTO v_attempt_id;

  INSERT INTO public.user_answers(
    user_id, question_id, quiz_attempt_id, selected_option,
    is_correct, answered_at
  )
  SELECT user_id, question_id, v_attempt_id, selected_option, is_correct, answered_at
  FROM public.quiz_answers
  WHERE session_id = v_session.id AND user_id = v_user_id;

  RETURN jsonb_build_object(
    'attempt_id', v_attempt_id,
    'total_questions', v_session.total_questions,
    'correct_answers', v_correct,
    'wrong_answers', v_wrong,
    'blank_answers', v_blank,
    'duration_seconds', v_duration,
    'net', v_net
  );
END;
$$;


CREATE OR REPLACE FUNCTION public.abandon_quiz_session(p_session_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  UPDATE public.quiz_sessions
  SET status = 'abandoned', completed_at = NOW()
  WHERE id = p_session_id AND user_id = v_user_id AND status = 'active';
  IF NOT FOUND THEN RAISE EXCEPTION 'SESSION_NOT_FOUND'; END IF;
  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION public.abandon_quiz_session(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.abandon_quiz_session(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.submit_quiz_answer(UUID,UUID,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_quiz_session(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_quiz_answer(UUID,UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_quiz_session(UUID) TO authenticated;


-- Start a quiz from the authenticated user's unresolved error notebook.
CREATE OR REPLACE FUNCTION public.start_error_quiz_session(
  p_subject_id UUID,
  p_question_count INTEGER,
  p_is_timed BOOLEAN DEFAULT TRUE,
  p_time_limit_seconds INTEGER DEFAULT 1800
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_session_id UUID;
  v_question_ids UUID[];
  v_count INTEGER;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF p_question_count IS NULL OR p_question_count < 1 OR p_question_count > 100 THEN
    RAISE EXCEPTION 'INVALID_QUESTION_COUNT';
  END IF;
  IF p_is_timed AND (p_time_limit_seconds IS NULL OR p_time_limit_seconds < 60 OR p_time_limit_seconds > 10800) THEN
    RAISE EXCEPTION 'INVALID_TIME_LIMIT';
  END IF;

  SELECT ARRAY_AGG(q.id ORDER BY q.random_key)
  INTO v_question_ids
  FROM (
    SELECT q.id, random() AS random_key
    FROM public.questions q
    JOIN public.error_notebook e ON e.question_id = q.id
    WHERE e.user_id = v_user_id
      AND COALESCE(e.is_resolved, FALSE) = FALSE
      AND q.subject_id = p_subject_id
      AND q.is_deleted = FALSE
    ORDER BY random_key
    LIMIT p_question_count
  ) q;

  v_count := COALESCE(array_length(v_question_ids, 1), 0);
  IF v_count = 0 THEN RAISE EXCEPTION 'NO_ERROR_QUESTIONS'; END IF;

  INSERT INTO public.quiz_sessions(
    user_id, subject_id, question_ids, total_questions,
    is_timed, time_limit_seconds
  ) VALUES (
    v_user_id, p_subject_id, v_question_ids, v_count,
    p_is_timed, CASE WHEN p_is_timed THEN p_time_limit_seconds ELSE NULL END
  ) RETURNING id INTO v_session_id;

  RETURN jsonb_build_object(
    'session_id', v_session_id,
    'subject_id', p_subject_id,
    'question_ids', v_question_ids,
    'total_questions', v_count,
    'is_timed', p_is_timed,
    'time_limit_seconds', CASE WHEN p_is_timed THEN p_time_limit_seconds ELSE NULL END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.start_error_quiz_session(UUID,INTEGER,BOOLEAN,INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.start_error_quiz_session(UUID,INTEGER,BOOLEAN,INTEGER) TO authenticated;

COMMIT;
