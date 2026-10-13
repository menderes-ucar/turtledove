-- BESTIE call signaling compatibility hardening.
-- Run once on the deployed Supabase database.
-- The call client uses: accept, reject, hangup, offer, answer, ice, media_state.
-- Older installations may have a CHECK constraint that rejects media_state.

DO $$
DECLARE
  c record;
BEGIN
  FOR c IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'public.call_signals'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%type%'
  LOOP
    EXECUTE format(
      'ALTER TABLE public.call_signals DROP CONSTRAINT IF EXISTS %I',
      c.conname
    );
  END LOOP;
END $$;

ALTER TABLE public.call_signals
  ALTER COLUMN id SET DEFAULT gen_random_uuid();

ALTER TABLE public.call_signals
  ALTER COLUMN data SET DEFAULT '{}'::jsonb;

ALTER TABLE public.call_signals
  ALTER COLUMN created_at SET DEFAULT now();

ALTER TABLE public.call_signals
  ADD CONSTRAINT call_signal_type_check
  CHECK (type IN (
    'accept',
    'reject',
    'hangup',
    'offer',
    'answer',
    'ice',
    'media_state',
    'renegotiate_request'
  ));

NOTIFY pgrst, 'reload schema';
