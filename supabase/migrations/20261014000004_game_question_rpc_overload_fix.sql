-- Use a unique RPC name so PostgREST cannot confuse the one-argument legacy
-- function with the localized two-argument function.
BEGIN;

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
  IF v_language NOT IN ('tr', 'en', 'de', 'es', 'fr') THEN
    v_language := 'en';
  END IF;

  SELECT * INTO q
  FROM public.game_questions
  WHERE id = p_question_id AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'GAME_QUESTION_NOT_FOUND';
  END IF;

  v_translation := q.translations -> v_language;
  IF v_translation IS NULL OR jsonb_typeof(v_translation) <> 'object' THEN
    v_translation := q.translations -> 'en';
  END IF;

  id := q.id;
  game_type := q.game_type;
  category := coalesce(v_translation ->> 'category', q.category);
  subcategory := coalesce(v_translation ->> 'subcategory', q.subcategory);
  prompt := coalesce(v_translation ->> 'prompt', q.prompt);
  question_type := q.question_type;
  options := CASE
    WHEN jsonb_typeof(v_translation -> 'options') = 'array'
      THEN v_translation -> 'options'
    ELSE q.options
  END;
  correct_answer := CASE WHEN q.game_type = 'trivia' THEN NULL ELSE q.correct_answer END;
  difficulty := q.difficulty;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.get_game_question_public_localized(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_game_question_public_localized(uuid, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;
