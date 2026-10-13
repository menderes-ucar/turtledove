-- BESTIE 44: live game runtime compatibility
--
-- The Word Chain V3/V4 RPCs use ON CONFLICT(session_id). Older live schemas
-- may have the same column without a UNIQUE/PK constraint, which produces:
--   42P10: there is no unique or exclusion constraint matching ON CONFLICT
--
-- game_word_sessions is logically one runtime row per generic game session,
-- so session_id must be unique.

BEGIN;

DO $$
BEGIN
  IF to_regclass('public.game_word_sessions') IS NOT NULL THEN
    -- The intended schema already has session_id as its primary key. This
    -- CREATE UNIQUE INDEX is therefore a no-op there and repairs older
    -- deployments where the column existed without a uniqueness constraint.
    CREATE UNIQUE INDEX IF NOT EXISTS bestie_game_word_sessions_session_uidx
      ON public.game_word_sessions(session_id);
  END IF;
END $$;

-- Ensure the latest generic-game round transition function is available even
-- when the migration is re-run against an older live database. The actual
-- implementation is supplied by migration 43; this migration intentionally
-- does not duplicate it.

NOTIFY pgrst, 'reload schema';

COMMIT;
