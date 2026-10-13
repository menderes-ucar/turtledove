-- Phase 2 architecture hardening: normalize error notebook naming and lock direct question access.
ALTER TABLE public.error_notebook ADD COLUMN IF NOT EXISTS note_text text;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='error_notebook' AND column_name='resolved') THEN NULL; END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_error_notebook_user_resolved ON public.error_notebook(user_id,resolved,last_wrong_at DESC);
REVOKE SELECT ON public.questions FROM anon, authenticated;
