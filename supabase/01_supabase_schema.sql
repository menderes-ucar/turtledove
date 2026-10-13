-- ============================================================================
-- KPSS MOBIL UYGULAMASI - SUPABASE (PostgreSQL) ŞEMASI
-- Production-Ready: RLS, Indexler, Auth Integration
-- ============================================================================

-- 1. ENUM TYPES
-- ============================================================================

CREATE TYPE exam_type AS ENUM ('lisans', 'onlisans', 'ortaogretim');
CREATE TYPE quiz_status AS ENUM ('running', 'completed', 'abandoned');

-- 2. TABLES
-- ============================================================================

-- Kullanıcı Profilleri (auth.users ile link)
CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL UNIQUE,
    full_name TEXT,
    target_exam exam_type NOT NULL DEFAULT 'lisans',
    target_score INTEGER CHECK (target_score >= 0 AND target_score <= 100),
    is_premium BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Sınav Kategorileri (Sözel, Sayısal vb.)
CREATE TABLE IF NOT EXISTS categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    icon_name TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Kategoriler altında konular (Tarih, Coğrafya, Matematik vb.)
CREATE TABLE IF NOT EXISTS subjects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id UUID NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    icon_name TEXT,
    difficulty_order INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(category_id, name)
);

-- Soru Havuzu
CREATE TABLE IF NOT EXISTS questions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subject_id UUID NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
    question_text TEXT NOT NULL,
    image_url TEXT,
    option_a TEXT NOT NULL,
    option_b TEXT NOT NULL,
    option_c TEXT NOT NULL,
    option_d TEXT NOT NULL,
    option_e TEXT,
    correct_option CHAR(1) NOT NULL CHECK (correct_option IN ('A', 'B', 'C', 'D', 'E')),
    explanation TEXT,
    difficulty_level INTEGER CHECK (difficulty_level BETWEEN 1 AND 5),
    source TEXT,
    year INTEGER,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Kullanıcı Sınav Oturumları
CREATE TABLE IF NOT EXISTS user_quiz_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    subject_id UUID NOT NULL REFERENCES subjects(id) ON DELETE RESTRICT,
    status quiz_status DEFAULT 'running',
    total_questions INTEGER NOT NULL,
    correct_answers INTEGER DEFAULT 0,
    wrong_answers INTEGER DEFAULT 0,
    blank_answers INTEGER DEFAULT 0,
    duration_seconds INTEGER DEFAULT 0,
    score NUMERIC(5,2),
    is_timed BOOLEAN DEFAULT TRUE,
    time_limit_seconds INTEGER,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Kullanıcı Soru Cevapları
CREATE TABLE IF NOT EXISTS user_answers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    question_id UUID NOT NULL REFERENCES questions(id) ON DELETE RESTRICT,
    quiz_attempt_id UUID NOT NULL REFERENCES user_quiz_attempts(id) ON DELETE CASCADE,
    selected_option CHAR(1),
    is_correct BOOLEAN,
    time_spent_seconds INTEGER,
    answered_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Akıllı Yanlış Defteri
CREATE TABLE IF NOT EXISTS error_notebook (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    question_id UUID NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
    resolved BOOLEAN DEFAULT FALSE,
    wrong_count INTEGER DEFAULT 1,
    last_wrong_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    note_text TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, question_id)
);

-- Kullanıcı Notları
CREATE TABLE IF NOT EXISTS notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    subject_id UUID REFERENCES subjects(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- AI Oluşturulan Çalışma Planları
CREATE TABLE IF NOT EXISTS ai_study_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    plan_data JSONB NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Kullanıcı Cihazları (FCM Token Yönetimi)
CREATE TABLE IF NOT EXISTS user_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    fcm_token TEXT NOT NULL,
    platform TEXT NOT NULL CHECK (platform IN ('android', 'ios')),
    device_name TEXT,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, fcm_token)
);

-- 3. INDEXES
-- ============================================================================

CREATE INDEX idx_questions_subject_id ON questions(subject_id) WHERE is_deleted = FALSE;
CREATE INDEX idx_questions_difficulty ON questions(difficulty_level);
CREATE INDEX idx_user_quiz_attempts_user_id ON user_quiz_attempts(user_id);
CREATE INDEX idx_user_quiz_attempts_status ON user_quiz_attempts(status);
CREATE INDEX idx_user_answers_user_id ON user_answers(user_id);
CREATE INDEX idx_user_answers_quiz_attempt_id ON user_answers(quiz_attempt_id);
CREATE INDEX idx_error_notebook_user_id ON error_notebook(user_id);
CREATE INDEX idx_error_notebook_resolved ON error_notebook(resolved) WHERE resolved = FALSE;
CREATE INDEX idx_notes_user_id ON notes(user_id);
CREATE INDEX idx_ai_study_plans_user_id ON ai_study_plans(user_id);
CREATE INDEX idx_user_devices_user_id ON user_devices(user_id);
CREATE INDEX idx_user_devices_fcm_token ON user_devices(fcm_token);

-- 4. ENABLE RLS (Row Level Security)
-- ============================================================================

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE subjects ENABLE ROW LEVEL SECURITY;
ALTER TABLE questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_quiz_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_answers ENABLE ROW LEVEL SECURITY;
ALTER TABLE error_notebook ENABLE ROW LEVEL SECURITY;
ALTER TABLE notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_study_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_devices ENABLE ROW LEVEL SECURITY;

-- 5. RLS POLICIES - PROFILES
-- ============================================================================

-- Profil okuma: kendi profilini ve admin profil görüntüleyebilir
CREATE POLICY "Profiles readable by owner" ON profiles
    FOR SELECT USING (auth.uid() = id);

-- Profil güncelleme: sadece kendi profili
CREATE POLICY "Profiles updatable by owner" ON profiles
    FOR UPDATE USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- 6. RLS POLICIES - CATEGORIES & SUBJECTS (Herkese açık - okuma)
-- ============================================================================

CREATE POLICY "Categories publicly readable" ON categories
    FOR SELECT USING (TRUE);

CREATE POLICY "Subjects publicly readable" ON subjects
    FOR SELECT USING (TRUE);

-- 7. RLS POLICIES - QUESTIONS (Herkese açık - okuma)
-- ============================================================================

CREATE POLICY "Questions publicly readable" ON questions
    FOR SELECT USING (is_deleted = FALSE);

-- 8. RLS POLICIES - USER_QUIZ_ATTEMPTS
-- ============================================================================

-- Kendi quiz oturumlarını görüntüle
CREATE POLICY "User quiz attempts readable by owner" ON user_quiz_attempts
    FOR SELECT USING (auth.uid() = user_id);

-- Kendi quiz oturumlarını oluştur
CREATE POLICY "User quiz attempts insertable by owner" ON user_quiz_attempts
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Kendi quiz oturumlarını güncelle
CREATE POLICY "User quiz attempts updatable by owner" ON user_quiz_attempts
    FOR UPDATE USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- 9. RLS POLICIES - USER_ANSWERS
-- ============================================================================

-- Kendi cevaplarını görüntüle
CREATE POLICY "User answers readable by owner" ON user_answers
    FOR SELECT USING (auth.uid() = user_id);

-- Kendi cevaplarını oluştur
CREATE POLICY "User answers insertable by owner" ON user_answers
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- 10. RLS POLICIES - ERROR_NOTEBOOK
-- ============================================================================

-- Kendi yanlış defterini görüntüle
CREATE POLICY "Error notebook readable by owner" ON error_notebook
    FOR SELECT USING (auth.uid() = user_id);

-- Kendi yanlış defterini oluştur/güncelle
CREATE POLICY "Error notebook insertable by owner" ON error_notebook
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Error notebook updatable by owner" ON error_notebook
    FOR UPDATE USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- 11. RLS POLICIES - NOTES
-- ============================================================================

-- Kendi notlarını görüntüle
CREATE POLICY "Notes readable by owner" ON notes
    FOR SELECT USING (auth.uid() = user_id);

-- Kendi notlarını oluştur
CREATE POLICY "Notes insertable by owner" ON notes
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Kendi notlarını güncelle
CREATE POLICY "Notes updatable by owner" ON notes
    FOR UPDATE USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Kendi notlarını sil
CREATE POLICY "Notes deletable by owner" ON notes
    FOR DELETE USING (auth.uid() = user_id);

-- 12. RLS POLICIES - AI_STUDY_PLANS
-- ============================================================================

-- Kendi planlarını görüntüle
CREATE POLICY "Study plans readable by owner" ON ai_study_plans
    FOR SELECT USING (auth.uid() = user_id);

-- Kendi planlarını oluştur
CREATE POLICY "Study plans insertable by owner" ON ai_study_plans
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Kendi planlarını güncelle
CREATE POLICY "Study plans updatable by owner" ON ai_study_plans
    FOR UPDATE USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- 13. RLS POLICIES - USER_DEVICES
-- ============================================================================

-- Kendi cihazlarını görüntüle
CREATE POLICY "User devices readable by owner" ON user_devices
    FOR SELECT USING (auth.uid() = user_id);

-- Kendi cihazlarını oluştur
CREATE POLICY "User devices insertable by owner" ON user_devices
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Kendi cihazlarını güncelle
CREATE POLICY "User devices updatable by owner" ON user_devices
    FOR UPDATE USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- 14. TRIGGER FUNCTIONS
-- ============================================================================

-- Auth.users'dan profile otomatik oluşturma
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, email, full_name)
    VALUES (
        new.id,
        new.email,
        COALESCE(new.raw_user_meta_data->>'full_name', '')
    );
    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Trigger oluştur
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Updated_at trigger fonksiyonu
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    new.updated_at = NOW();
    RETURN new;
END;
$$ LANGUAGE plpgsql;

-- Updated_at triggerları
CREATE TRIGGER update_profiles_updated_at
    BEFORE UPDATE ON profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_categories_updated_at
    BEFORE UPDATE ON categories
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_subjects_updated_at
    BEFORE UPDATE ON subjects
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_questions_updated_at
    BEFORE UPDATE ON questions
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_error_notebook_updated_at
    BEFORE UPDATE ON error_notebook
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_notes_updated_at
    BEFORE UPDATE ON notes
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_ai_study_plans_updated_at
    BEFORE UPDATE ON ai_study_plans
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- 15. SEED DATA (Örnek veri)
-- ============================================================================

-- Kategoriler
INSERT INTO categories (name, icon_name) VALUES
    ('Sözel', 'verbal_icon'),
    ('Sayısal', 'numerical_icon'),
    ('Tamamlayıcı', 'complementary_icon')
ON CONFLICT DO NOTHING;

-- Sözel Kategorisinin Konuları
INSERT INTO subjects (category_id, name, description, difficulty_order) VALUES
    ((SELECT id FROM categories WHERE name = 'Sözel'), 'Tarih', 'KPSS Tarih Konuları', 1),
    ((SELECT id FROM categories WHERE name = 'Sözel'), 'Coğrafya', 'KPSS Coğrafya Konuları', 2),
    ((SELECT id FROM categories WHERE name = 'Sözel'), 'Türkçe', 'KPSS Türkçe Konuları', 3),
    ((SELECT id FROM categories WHERE name = 'Sayısal'), 'Matematik', 'KPSS Matematik Konuları', 1),
    ((SELECT id FROM categories WHERE name = 'Sayısal'), 'Geometri', 'KPSS Geometri Konuları', 2),
    ((SELECT id FROM categories WHERE name = 'Tamamlayıcı'), 'Anayasa', 'KPSS Anayasa Konuları', 1),
    ((SELECT id FROM categories WHERE name = 'Tamamlayıcı'), 'İdari Yargı', 'KPSS İdari Yargı Konuları', 2)
ON CONFLICT DO NOTHING;

-- Örnek Soru (Tarih)
INSERT INTO questions (
    subject_id, question_text, option_a, option_b, option_c, option_d, option_e,
    correct_option, difficulty_level, year, explanation
) VALUES (
    (SELECT id FROM subjects WHERE name = 'Tarih' LIMIT 1),
    'Osmanlı İmparatorluğunun kurulduğu yıl hangisidir?',
    '1299',
    '1453',
    '1876',
    '1922',
    '1071',
    'A',
    2,
    2023,
    'Osmanlı İmparatorluğu 1299 yılında Osman Bey tarafından kurulmuştur.'
) ON CONFLICT DO NOTHING;

-- 16. VIEWS (İsteğe bağlı - sık kullanılan sorgular)
-- ============================================================================

-- Kullanıcının en son quiz sonuçları
CREATE OR REPLACE VIEW user_quiz_summary AS
SELECT
    u.id as user_id,
    u.full_name,
    s.name as subject_name,
    uqa.id as attempt_id,
    uqa.status,
    uqa.total_questions,
    uqa.correct_answers,
    uqa.wrong_answers,
    uqa.score,
    uqa.completed_at,
    ROUND(
        (uqa.correct_answers::NUMERIC / NULLIF(uqa.total_questions, 0) * 100)::NUMERIC,
        2
    ) as success_percentage
FROM user_quiz_attempts uqa
JOIN profiles u ON uqa.user_id = u.id
JOIN subjects s ON uqa.subject_id = s.id
WHERE uqa.status = 'completed'
ORDER BY uqa.completed_at DESC;

-- Yanlış yapılan sorular özet
CREATE OR REPLACE VIEW user_error_summary AS
SELECT
    en.user_id,
    en.question_id,
    q.subject_id,
    s.name as subject_name,
    q.question_text,
    en.wrong_count,
    en.last_wrong_at,
    en.resolved
FROM error_notebook en
JOIN questions q ON en.question_id = q.id
JOIN subjects s ON q.subject_id = s.id
ORDER BY en.wrong_count DESC, en.last_wrong_at DESC;

-- ============================================================================
-- END OF SUPABASE SCHEMA
-- ============================================================================
