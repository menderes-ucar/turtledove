// ============================================================================
// KPSS KOLAY - CRITICAL SECURITY & LOGIC FIXES
// 10 serious production issues fixed with actual code
// ============================================================================

// ============================================================================
// PROBLEM 1: RANDOM() ORDER BY LIMIT - SQL BUG
// ============================================================================

// BEFORE (WRONG):
/*
SELECT ARRAY_AGG(id)
INTO v_question_ids
FROM questions
WHERE subject_id = p_subject_id
  AND is_deleted = FALSE
ORDER BY RANDOM()
LIMIT p_question_count;
*/

// AFTER (CORRECT):
SELECT ARRAY_AGG(q.id) INTO v_question_ids
FROM (
    SELECT id
    FROM questions
    WHERE subject_id = p_subject_id
      AND is_deleted = FALSE
    ORDER BY RANDOM()
    LIMIT p_question_count
) q;

// ============================================================================
// PROBLEM 2: QUIZ PARAMETER VALIDATION - NO BOUNDS CHECK
// ============================================================================

// ADD to start_quiz_session RPC (BEGINNING):
IF p_question_count < 1 OR p_question_count > 100 THEN
    RAISE EXCEPTION 'Invalid question count: must be 1-100';
END IF;

IF p_time_limit_minutes < 1 OR p_time_limit_minutes > 180 THEN
    RAISE EXCEPTION 'Invalid time limit: must be 1-180 minutes';
END IF;

IF p_subject_id IS NULL OR p_subject_id = '00000000-0000-0000-0000-000000000000' THEN
    RAISE EXCEPTION 'Invalid subject ID';
END IF;

// ============================================================================
// PROBLEM 3: SESSION QUESTION VALIDATION - CROSS-SESSION CHEATING
// ============================================================================

// ADD to submit_quiz_answer RPC (AFTER session validation):
IF NOT p_question_id = ANY(v_session_record.question_ids) THEN
    RAISE EXCEPTION 'Question does not belong to this quiz session';
END IF;

// ============================================================================
// PROBLEM 4: DUPLICATE ANSWERS - NO UNIQUE CONSTRAINT
// ============================================================================

// ADD to schema (run in migration):
ALTER TABLE quiz_answers
ADD CONSTRAINT quiz_answers_session_question_unique
UNIQUE (session_id, question_id);

// Handling duplicates in RPC:
BEGIN
    INSERT INTO quiz_answers (
        session_id,
        user_id,
        question_id,
        selected_option,
        is_correct
    ) VALUES (
        p_session_id,
        v_user_id,
        p_question_id,
        p_selected_option,
        v_is_correct
    );
EXCEPTION WHEN unique_violation THEN
    UPDATE quiz_answers
    SET 
        selected_option = p_selected_option,
        is_correct = v_is_correct,
        updated_at = NOW()
    WHERE session_id = p_session_id
      AND question_id = p_question_id;
END;

// ============================================================================
// PROBLEM 5: SELECTED_OPTION VALIDATION - ANYTHING ACCEPTED
// ============================================================================

// ADD to submit_quiz_answer RPC (BEFORE insert):
IF UPPER(TRIM(p_selected_option)) NOT IN ('A','B','C','D','E') THEN
    RAISE EXCEPTION 'Invalid option. Must be A, B, C, D, or E';
END IF;

// ============================================================================
// PROBLEM 6: TIMER SERVER-SIDE VALIDATION - CLIENT TIME MANIPULATION
// ============================================================================

// ADD to submit_quiz_answer RPC (AFTER session fetch):
IF v_session_record.is_timed THEN
    IF NOW() > v_session_record.started_at + 
       (v_session_record.time_limit_seconds * INTERVAL '1 second') THEN
        RAISE EXCEPTION 'Quiz time has expired';
    END IF;
END IF;

// Also add to complete_quiz_session RPC:
IF v_session_record.is_timed THEN
    IF NOW() > v_session_record.started_at + 
       (v_session_record.time_limit_seconds * INTERVAL '1 second') THEN
        RAISE EXCEPTION 'Cannot complete: time limit exceeded';
    END IF;
END IF;

// ============================================================================
// PROBLEM 7: SUBJECT_ID PARAMETER TRUST - CLIENT CAN LIE
// ============================================================================

// BEFORE:
/*
complete_quiz_session(
    p_session_id UUID,
    p_subject_id UUID  -- CLIENT CAN LIE
)
*/

// AFTER - Don't trust client:
-- Remove p_subject_id parameter
-- Use session's subject:
INSERT INTO user_quiz_attempts (
    user_id,
    subject_id,  -- FROM v_session_record.subject_id, NOT client
    ...
) VALUES (
    v_user_id,
    v_session_record.subject_id,  -- SERVER TRUTH
    ...
);

// ============================================================================
// PROBLEM 8: USER_ID FROM CLIENT - SECURITY DEFINER DANGER
// ============================================================================

// BEFORE:
/*
upsert_error_notebook(
    p_user_id UUID,  -- CLIENT PROVIDED
    ...
)
*/

// AFTER - Always use auth.uid():
CREATE OR REPLACE FUNCTION upsert_error_notebook(
    p_question_id UUID,
    p_subject_id UUID,
    p_subject_name TEXT,
    p_question_text TEXT,
    p_user_selected_option TEXT,
    p_correct_option TEXT
)
RETURNS JSON AS $$
DECLARE
    v_user_id UUID := auth.uid();  -- GET FROM AUTH, NOT PARAM
    v_error_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User not authenticated';
    END IF;
    -- ... rest of function
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

// ============================================================================
// PROBLEM 9: QUIZ SESSION UPDATE POLICY - CLIENT CAN MODIFY
// ============================================================================

// BEFORE:
/*
CREATE POLICY "Users can update own sessions"
ON quiz_sessions FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);  -- TOO PERMISSIVE
*/

// AFTER - Only allow RPC to change status:
DROP POLICY "Users can update own sessions" ON quiz_sessions;

-- No UPDATE policy for users - only RPC via SECURITY DEFINER
-- RPC functions handle state transitions securely

-- Users can only SELECT their own sessions:
CREATE POLICY "Users can view own sessions"
ON quiz_sessions FOR SELECT
USING (auth.uid() = user_id);

-- INSERT only via RPC:
CREATE POLICY "System can create sessions"
ON quiz_sessions FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- DELETE not allowed:
-- (no DELETE policy = no direct deletes)

// ============================================================================
// PROBLEM 10: ERROR NOTEBOOK UI INTEGRATION - REAL BACKEND CALL
// ============================================================================

// FILE: lib/screens/error_notebook_screen.dart
// REPLACE mock TODO with real provider call:

// BEFORE (mock):
/*
void _markAsResolved(BuildContext context, String errorId) {
    // TODO: Supabase'de mark as resolved
    setState(() {
        _resolvedErrors.add(errorId);
    });
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Çözüldü olarak işaretlendi'))
    );
}
*/

// AFTER (real):
void _markAsResolved(BuildContext context, String errorId) {
    final provider = Provider.of<ErrorNotebookProvider>(
        context,
        listen: false,
    );
    
    provider.markAsResolved(errorId).then((_) {
        if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('✅ Çözüldü olarak işaretlendi'),
                    duration: Duration(seconds: 2),
                ),
            );
        }
    }).catchError((error) {
        if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text('❌ Hata: $error'),
                    backgroundColor: Colors.red,
                ),
            );
        }
    });
}

// Also fix note editing:
void _editErrorNote(BuildContext context, ErrorNotebookItemModel error) {
    final noteController = TextEditingController(text: error.userNote ?? '');
    
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
            title: const Text('Not Ekle'),
            content: TextField(
                controller: noteController,
                decoration: const InputDecoration(
                    hintText: 'Bu hata hakkında not yazın...',
                ),
                maxLines: 3,
            ),
            actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('İptal'),
                ),
                ElevatedButton(
                    onPressed: () {
                        final provider = Provider.of<ErrorNotebookProvider>(
                            context,
                            listen: false,
                        );
                        
                        provider.updateNote(error.id, noteController.text)
                            .then((_) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('✅ Not kaydedildi')),
                                );
                            })
                            .catchError((error) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('❌ Hata: $error')),
                                );
                            });
                    },
                    child: const Text('Kaydet'),
                ),
            ],
        ),
    );
}

// ============================================================================
// BONUS FIX: SECURITY DEFINER HARDENING
// ============================================================================

-- ADD to ALL SECURITY DEFINER functions:

SET search_path = public, pg_temp;

-- EXAMPLE:
CREATE OR REPLACE FUNCTION submit_quiz_answer(...)
RETURNS JSON AS $$
#variable_conflict use_column
BEGIN
    SET search_path = public, pg_temp;
    -- ... function body
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- GRANT management:
REVOKE ALL ON FUNCTION submit_quiz_answer(...) FROM PUBLIC;
REVOKE ALL ON FUNCTION submit_quiz_answer(...) FROM authenticated;
GRANT EXECUTE ON FUNCTION submit_quiz_answer(...) TO authenticated;

// ============================================================================
// CRITICAL TODO - SCHEMA INCONSISTENCY FIX
// ============================================================================

-- BEFORE: resolved vs is_resolved inconsistency
-- AFTER: Standardize on is_resolved everywhere

-- Migration:
ALTER TABLE error_notebook
RENAME COLUMN resolved TO is_resolved;

-- Update all views/queries to use is_resolved
-- Update all Dart models to use isResolved

// ============================================================================
// ANALYTICS RLS SECURITY FIX
// ============================================================================

-- BEFORE:
/*
CREATE OR REPLACE FUNCTION get_subject_analytics(p_user_id UUID)
RETURNS TABLE(...) AS $$
BEGIN
    SELECT ... WHERE user_id = p_user_id;
END;
*/

-- AFTER - Use auth.uid():
CREATE OR REPLACE FUNCTION get_subject_analytics()
RETURNS TABLE(...) AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User not authenticated';
    END IF;
    
    SELECT ... WHERE user_id = v_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Dart call changes:
// BEFORE: rpc('get_subject_analytics', params: {'p_user_id': userId})
// AFTER:  rpc('get_subject_analytics') -- No params, uses auth context

// ============================================================================
// QUIZ ATTEMPT TIMESTAMP FIX
// ============================================================================

-- VALIDATE in complete_quiz_session:
IF NOW() < v_session_record.started_at THEN
    RAISE EXCEPTION 'Invalid quiz session: future start time';
END IF;

IF EXTRACT(EPOCH FROM (NOW() - v_session_record.started_at)) < 10 THEN
    -- Quiz completed in less than 10 seconds = likely abuse
    INSERT INTO audit_log (user_id, action, details)
    VALUES (v_user_id, 'SUSPICIOUS_QUIZ_COMPLETION', 
            json_build_object('duration_seconds', 
                EXTRACT(EPOCH FROM (NOW() - v_session_record.started_at))));
END IF;

// ============================================================================
// COMPLETE FIXED RPC TEMPLATE
// ============================================================================

/*
CREATE OR REPLACE FUNCTION submit_quiz_answer(
    p_session_id UUID,
    p_question_id UUID,
    p_selected_option TEXT
)
RETURNS JSON AS $$
#variable_conflict use_column
DECLARE
    v_user_id UUID;
    v_correct_option TEXT;
    v_is_correct BOOLEAN;
    v_answer_id UUID;
    v_explanation TEXT;
    v_session_record RECORD;
    v_question_record RECORD;
BEGIN
    SET search_path = public, pg_temp;
    v_user_id := auth.uid();
    
    -- VALIDATION 1: User authenticated
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User not authenticated';
    END IF;

    -- VALIDATION 2: Option format
    IF UPPER(TRIM(p_selected_option)) NOT IN ('A','B','C','D','E') THEN
        RAISE EXCEPTION 'Invalid option: must be A-E';
    END IF;

    -- VALIDATION 3: Session exists & belongs to user
    SELECT * INTO v_session_record
    FROM quiz_sessions
    WHERE id = p_session_id
      AND user_id = v_user_id
      AND status = 'active'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Quiz session not found or inactive';
    END IF;

    -- VALIDATION 4: Question belongs to this session
    IF NOT p_question_id = ANY(v_session_record.question_ids) THEN
        RAISE EXCEPTION 'Question does not belong to this quiz';
    END IF;

    -- VALIDATION 5: Time check
    IF v_session_record.is_timed THEN
        IF NOW() > v_session_record.started_at + 
           (v_session_record.time_limit_seconds * INTERVAL '1 second') THEN
            RAISE EXCEPTION 'Quiz time has expired';
        END IF;
    END IF;

    -- VALIDATION 6: Duplicate answer check
    IF EXISTS (
        SELECT 1 FROM quiz_answers
        WHERE session_id = p_session_id
          AND question_id = p_question_id
    ) THEN
        RAISE EXCEPTION 'Answer already submitted for this question';
    END IF;

    -- Get question & calculate correctness
    SELECT correct_option, explanation INTO v_correct_option, v_explanation
    FROM questions
    WHERE id = p_question_id AND is_deleted = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Question not found';
    END IF;

    -- SERVER CALCULATES CORRECTNESS
    v_is_correct := UPPER(TRIM(p_selected_option)) = UPPER(v_correct_option);

    -- Insert answer
    INSERT INTO quiz_answers (
        session_id, user_id, question_id, selected_option, is_correct
    ) VALUES (p_session_id, v_user_id, p_question_id, p_selected_option, v_is_correct)
    RETURNING id INTO v_answer_id;

    -- Add to error notebook if wrong
    IF NOT v_is_correct THEN
        INSERT INTO error_notebook (
            user_id, question_id, subject_id, subject_name,
            question_text, user_selected_option, correct_option,
            wrong_count, last_wrong_at, is_resolved
        ) SELECT
            v_user_id, q.id, q.subject_id, s.name, q.question_text,
            p_selected_option, v_correct_option, 1, NOW(), FALSE
        FROM questions q JOIN subjects s ON q.subject_id = s.id
        WHERE q.id = p_question_id
        ON CONFLICT (user_id, question_id) DO UPDATE
        SET wrong_count = error_notebook.wrong_count + 1,
            last_wrong_at = NOW();
    END IF;

    RETURN json_build_object(
        'id', v_answer_id,
        'is_correct', v_is_correct,
        'correct_option', v_correct_option,
        'explanation', v_explanation,
        'earned_points', CASE WHEN v_is_correct THEN 1 ELSE 0 END
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION submit_quiz_answer(...) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION submit_quiz_answer(...) TO authenticated;
*/

// ============================================================================
// END OF CRITICAL FIXES
// ============================================================================
