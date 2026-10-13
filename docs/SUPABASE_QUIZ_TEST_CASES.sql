-- Manual integration test checklist. Execute as authenticated users in a test project.
-- These are assertions/checks, not seed data.

-- 1) Public question access must not expose answer keys.
-- Expected: direct SELECT from public.questions fails for authenticated client.
-- SELECT id, correct_option FROM public.questions LIMIT 1;

-- 2) Session start returns question IDs.
-- SELECT public.start_quiz_session('<SUBJECT_UUID>', 5, true, 600);

-- 3) Session questions contain no correct_option/explanation columns.
-- SELECT * FROM public.get_quiz_questions('<SESSION_UUID>');

-- 4) Submit a valid answer.
-- SELECT public.submit_quiz_answer('<SESSION_UUID>', '<QUESTION_UUID>', 'A');

-- 5) Submit the same question twice.
-- Expected: QUESTION_ALREADY_ANSWERED.

-- 6) Submit a question not belonging to the session.
-- Expected: QUESTION_NOT_IN_SESSION.

-- 7) Complete before timer expiry.
-- SELECT public.complete_quiz_session('<SESSION_UUID>');

-- 8) Start a timed quiz, wait beyond its limit, then complete.
-- Expected: completion succeeds and blank count includes unanswered questions.

-- 9) Abandon a second active session.
-- SELECT public.abandon_quiz_session('<SESSION_UUID>');
