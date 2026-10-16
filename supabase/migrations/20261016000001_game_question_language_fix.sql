-- Bestie: return game question text in the language currently selected in the app.
-- Supports both existing translation shapes:
-- Most Likely To: {"tr":"...", "en":"..."}
-- Trivia: {"tr":{"prompt":"...","options":[...],"correct":"..."}, ...}
-- Trivia answer key is intentionally never sent to the client.
BEGIN;
CREATE OR REPLACE FUNCTION public.get_game_question_public_localized(
  p_question_id uuid,
  p_language_code text DEFAULT NULL
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
  v_language text;
  v_translation jsonb;
  v_prompt text;
  v_options jsonb;
  v_correct text;
BEGIN
  v_language := lower(split_part(coalesce(nullif(trim(p_language_code), ''),
    (SELECT language_code FROM public.profiles WHERE id = auth.uid()), 'en'), '-', 1));
  IF v_language NOT IN ('tr','en','de','es','fr') THEN v_language := 'en'; END IF;

  SELECT * INTO q FROM public.game_questions
  WHERE id = p_question_id AND is_active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAME_QUESTION_NOT_FOUND'; END IF;

  v_translation := q.translations -> v_language;
  IF v_translation IS NULL THEN v_translation := q.translations -> 'en'; END IF;

  IF jsonb_typeof(v_translation) = 'string' THEN
    -- MLT translation values are plain strings.
    v_prompt := trim(both '"' from v_translation::text);
    v_options := q.options;
  ELSIF jsonb_typeof(v_translation) = 'object' THEN
    v_prompt := v_translation ->> 'prompt';
    v_options := CASE WHEN jsonb_typeof(v_translation -> 'options') = 'array'
                      THEN v_translation -> 'options' ELSE q.options END;
    v_correct := v_translation ->> 'correct';
  END IF;

  IF nullif(v_prompt, '') IS NULL THEN v_prompt := q.prompt; END IF;
  IF v_options IS NULL THEN v_options := q.options; END IF;

  id := q.id;
  game_type := q.game_type;
  category := q.category;
  subcategory := q.subcategory;
  prompt := v_prompt;
  question_type := q.question_type;
  options := v_options;
  -- Do not leak Trivia answers; MLT retains its existing answer field.
  correct_answer := CASE WHEN q.game_type = 'trivia' THEN NULL
                         ELSE coalesce(v_correct, q.correct_answer) END;
  difficulty := q.difficulty;
  RETURN NEXT;
END;
$$;
REVOKE ALL ON FUNCTION public.get_game_question_public_localized(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_game_question_public_localized(uuid, text) TO authenticated;
COMMIT;
