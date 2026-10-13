-- Public transport for Bestie game questions.
BEGIN;
ALTER TABLE public.game_questions ADD COLUMN IF NOT EXISTS translations jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE OR REPLACE FUNCTION public.get_game_question_public(p_question_id uuid)
RETURNS TABLE (
  id uuid, game_type text, category text, subcategory text, prompt text,
  question_type text, options jsonb, correct_answer text, difficulty text
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public, pg_temp
AS $$
DECLARE
  q public.game_questions%ROWTYPE;
  v_language text := COALESCE((SELECT language_code FROM public.profiles WHERE id=auth.uid()), 'en');
  v_translation jsonb;
BEGIN
  SELECT * INTO q FROM public.game_questions WHERE id=p_question_id AND is_active=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_QUESTION_NOT_FOUND'; END IF;

  v_translation := q.translations -> v_language;
  IF v_translation IS NULL OR jsonb_typeof(v_translation) <> 'object' THEN
    v_translation := q.translations -> 'en';
  END IF;

  id := q.id;
  game_type := q.game_type;
  category := q.category;
  subcategory := q.subcategory;
  prompt := COALESCE(v_translation->>'prompt', q.prompt);
  question_type := q.question_type;
  options := CASE WHEN jsonb_typeof(v_translation->'options')='array'
                  THEN v_translation->'options' ELSE q.options END;
  correct_answer := CASE WHEN q.game_type='trivia' THEN NULL ELSE q.correct_answer END;
  difficulty := q.difficulty;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.get_game_question_public(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_game_question_public(uuid) TO authenticated;
COMMIT;
