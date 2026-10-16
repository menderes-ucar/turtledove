-- Diagnostic only: list historical duplicate prompt occurrences within a pair/game type.
-- Does not modify data. Uses normalized base prompt text.
SELECT
  gs.game_type,
  LEAST(gs.created_by::text, gs.partner_id::text) AS user_a,
  GREATEST(gs.created_by::text, gs.partner_id::text) AS user_b,
  lower(regexp_replace(trim(gq.prompt), '\s+', ' ', 'g')) AS normalized_prompt,
  count(*) AS times_seen,
  array_agg(DISTINCT gq.id) AS question_ids,
  array_agg(gs.id) AS session_ids
FROM public.game_rounds gr
JOIN public.game_sessions gs ON gs.id = gr.session_id
JOIN public.game_questions gq ON gq.id = gr.question_id
WHERE gs.created_by IS NOT NULL AND gs.partner_id IS NOT NULL
GROUP BY gs.game_type,
  LEAST(gs.created_by::text, gs.partner_id::text),
  GREATEST(gs.created_by::text, gs.partner_id::text),
  lower(regexp_replace(trim(gq.prompt), '\s+', ' ', 'g'))
HAVING count(*) > 1
ORDER BY times_seen DESC;
