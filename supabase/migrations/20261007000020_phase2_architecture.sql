-- BESTIE / Quiz Phase 2 foundation + architecture hardening.
-- The legacy project contains the quiz schema in 01_supabase_schema.sql, but
-- those definitions were not part of the migration history. Production may
-- therefore be missing the quiz tables. Create only missing objects here.

-- Categories / subjects are required by questions and quiz RPCs.
CREATE TABLE IF NOT EXISTS public.categories (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL UNIQUE,
    icon_name text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.subjects (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id uuid,
    name text NOT NULL,
    description text,
    icon_name text,
    difficulty_order integer,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- Question pool. No hard FK is required for bootstrapping an existing DB;
-- the subject relation is added below when the referenced table exists.
CREATE TABLE IF NOT EXISTS public.questions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    subject_id uuid,
    question_text text NOT NULL,
    image_url text,
    option_a text NOT NULL,
    option_b text NOT NULL,
    option_c text NOT NULL,
    option_d text NOT NULL,
    option_e text,
    correct_option char(1) NOT NULL,
    explanation text,
    difficulty_level integer,
    source text,
    year integer,
    is_deleted boolean NOT NULL DEFAULT false,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS subject_id uuid;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS question_text text;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS image_url text;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS option_a text;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS option_b text;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS option_c text;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS option_d text;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS option_e text;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS correct_option char(1);
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS explanation text;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS difficulty_level integer;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS source text;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS year integer;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS is_deleted boolean NOT NULL DEFAULT false;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_questions_subject_id ON public.questions(subject_id);
CREATE INDEX IF NOT EXISTS idx_questions_difficulty ON public.questions(difficulty_level);

-- Error notebook. Supports both the legacy 'resolved' field and the newer
-- is_resolved/user_note names used by quiz_core_hardening_v2.
CREATE TABLE IF NOT EXISTS public.error_notebook (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL,
    question_id uuid NOT NULL,
    resolved boolean NOT NULL DEFAULT false,
    is_resolved boolean NOT NULL DEFAULT false,
    wrong_count integer NOT NULL DEFAULT 1,
    last_wrong_at timestamptz NOT NULL DEFAULT now(),
    note_text text,
    user_note text,
    subject_id uuid,
    subject_name text,
    question_text text,
    user_selected_option char(1),
    correct_option char(1),
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    UNIQUE(user_id, question_id)
);

ALTER TABLE public.error_notebook ADD COLUMN IF NOT EXISTS note_text text;
ALTER TABLE public.error_notebook ADD COLUMN IF NOT EXISTS user_note text;
ALTER TABLE public.error_notebook ADD COLUMN IF NOT EXISTS subject_id uuid;
ALTER TABLE public.error_notebook ADD COLUMN IF NOT EXISTS subject_name text;
ALTER TABLE public.error_notebook ADD COLUMN IF NOT EXISTS question_text text;
ALTER TABLE public.error_notebook ADD COLUMN IF NOT EXISTS user_selected_option char(1);
ALTER TABLE public.error_notebook ADD COLUMN IF NOT EXISTS correct_option char(1);
ALTER TABLE public.error_notebook ADD COLUMN IF NOT EXISTS is_resolved boolean NOT NULL DEFAULT false;
ALTER TABLE public.error_notebook ADD COLUMN IF NOT EXISTS wrong_count integer NOT NULL DEFAULT 1;
ALTER TABLE public.error_notebook ADD COLUMN IF NOT EXISTS last_wrong_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.error_notebook ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();
ALTER TABLE public.error_notebook ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='error_notebook' AND column_name='resolved') THEN
    UPDATE public.error_notebook SET is_resolved = COALESCE(resolved, false) WHERE is_resolved IS DISTINCT FROM COALESCE(resolved, false);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_error_notebook_user_resolved
  ON public.error_notebook(user_id,is_resolved,last_wrong_at DESC);

-- Active quiz session state used by the Phase 2 RPCs.
CREATE TABLE IF NOT EXISTS public.quiz_sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL,
    subject_id uuid NOT NULL,
    question_ids uuid[] NOT NULL,
    total_questions integer NOT NULL,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','completed','abandoned')),
    is_timed boolean NOT NULL DEFAULT true,
    time_limit_seconds integer,
    started_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_quiz_sessions_user_id ON public.quiz_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_quiz_sessions_status ON public.quiz_sessions(user_id,status);

CREATE TABLE IF NOT EXISTS public.quiz_answers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id uuid NOT NULL,
    user_id uuid NOT NULL,
    question_id uuid NOT NULL,
    selected_option char(1),
    is_correct boolean,
    answered_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(session_id, question_id)
);

CREATE INDEX IF NOT EXISTS idx_quiz_answers_session_id ON public.quiz_answers(session_id);
CREATE INDEX IF NOT EXISTS idx_quiz_answers_user_id ON public.quiz_answers(user_id);

-- Historical result tables used by complete_quiz_session.
CREATE TABLE IF NOT EXISTS public.user_quiz_attempts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL,
    subject_id uuid NOT NULL,
    status text NOT NULL DEFAULT 'running',
    total_questions integer NOT NULL,
    correct_answers integer DEFAULT 0,
    wrong_answers integer DEFAULT 0,
    blank_answers integer DEFAULT 0,
    duration_seconds integer DEFAULT 0,
    score numeric(8,2),
    is_timed boolean DEFAULT true,
    time_limit_seconds integer,
    started_at timestamptz DEFAULT now(),
    completed_at timestamptz,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.user_answers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL,
    question_id uuid NOT NULL,
    quiz_attempt_id uuid NOT NULL,
    selected_option char(1),
    is_correct boolean,
    time_spent_seconds integer,
    answered_at timestamptz DEFAULT now(),
    created_at timestamptz DEFAULT now()
);

-- Add safe foreign keys only when the referenced tables are present and the
-- constraint does not already exist. Existing production rows are preserved.
DO $$
BEGIN
  IF to_regclass('public.subjects') IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname='questions_subject_id_fkey'
      AND conrelid='public.questions'::regclass
  ) THEN
    ALTER TABLE public.questions
      ADD CONSTRAINT questions_subject_id_fkey
      FOREIGN KEY (subject_id) REFERENCES public.subjects(id) ON DELETE CASCADE;
  END IF;

  IF to_regclass('public.questions') IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname='error_notebook_question_id_fkey'
      AND conrelid='public.error_notebook'::regclass
  ) THEN
    ALTER TABLE public.error_notebook
      ADD CONSTRAINT error_notebook_question_id_fkey
      FOREIGN KEY (question_id) REFERENCES public.questions(id) ON DELETE CASCADE;
  END IF;
END $$;

-- Lock direct question access; quiz questions are served through SECURITY
-- DEFINER RPCs in migration 21.
REVOKE SELECT ON public.questions FROM anon, authenticated;

NOTIFY pgrst, 'reload schema';
