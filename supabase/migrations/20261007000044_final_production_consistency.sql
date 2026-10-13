-- BESTIE 44: final production consistency hardening
-- 1) Reassert non-recursive game_players RLS regardless of whether older
--    game migrations were applied in a different order.
-- 2) Make client-created notifications self-authorizing for push delivery.
-- 3) Make call sessions recoverable: heartbeat, stale-call reconciliation,
--    and activity timestamps.
-- 4) Keep this migration idempotent.

BEGIN;

-- ============================================================================
-- GAME PLAYERS: NEVER READ game_players FROM ITS OWN RLS POLICY
-- ============================================================================

CREATE OR REPLACE FUNCTION public.bestie_can_access_game_session_v44(
  p_session_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.game_sessions s
    WHERE s.id = p_session_id
      AND (s.created_by = auth.uid() OR s.partner_id = auth.uid())
  );
$$;

REVOKE ALL ON FUNCTION public.bestie_can_access_game_session_v44(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bestie_can_access_game_session_v44(uuid) TO authenticated;

DO $$
DECLARE
  p record;
BEGIN
  IF to_regclass('public.game_players') IS NULL THEN
    RETURN;
  END IF;

  FOR p IN
    SELECT polname
    FROM pg_policy
    WHERE polrelid = 'public.game_players'::regclass
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.game_players', p.polname);
  END LOOP;
END $$;

CREATE POLICY bestie_game_players_select_v44
ON public.game_players
FOR SELECT TO authenticated
USING (public.bestie_can_access_game_session_v44(session_id));

CREATE POLICY bestie_game_players_insert_v44
ON public.game_players
FOR INSERT TO authenticated
WITH CHECK (
  user_id = auth.uid()
  AND public.bestie_can_access_game_session_v44(session_id)
);

CREATE POLICY bestie_game_players_update_v44
ON public.game_players
FOR UPDATE TO authenticated
USING (
  user_id = auth.uid()
  AND public.bestie_can_access_game_session_v44(session_id)
)
WITH CHECK (
  user_id = auth.uid()
  AND public.bestie_can_access_game_session_v44(session_id)
);

CREATE POLICY bestie_game_players_delete_v44
ON public.game_players
FOR DELETE TO authenticated
USING (
  user_id = auth.uid()
  AND public.bestie_can_access_game_session_v44(session_id)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.game_players TO authenticated;

-- ============================================================================
-- NOTIFICATIONS: SERVER-OWNED SENDER ID
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_notification(
  p_user_id uuid,
  p_title text,
  p_body text,
  p_type text DEFAULT 'general',
  p_data jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
  v_event_key text;
  v_data jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  IF p_user_id <> auth.uid() AND NOT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid()
      AND paired_with = p_user_id
  ) THEN
    RAISE EXCEPTION 'not allowed to create notification for this user';
  END IF;

  -- Never trust sender_id supplied by a client. The database owns it.
  v_data := jsonb_set(
    coalesce(p_data, '{}'::jsonb),
    '{sender_id}',
    to_jsonb(auth.uid()),
    true
  );

  v_event_key := nullif(trim(coalesce(v_data->>'event_key', '')), '');

  IF v_event_key IS NOT NULL THEN
    SELECT id INTO v_id
    FROM public.notifications
    WHERE user_id = p_user_id
      AND data->>'event_key' = v_event_key
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_id IS NOT NULL THEN
      RETURN v_id;
    END IF;
  END IF;

  INSERT INTO public.notifications(user_id, title, body, type, data)
  VALUES (
    p_user_id,
    p_title,
    p_body,
    coalesce(nullif(trim(p_type), ''), 'general'),
    v_data
  )
  RETURNING id INTO v_id;

  RETURN v_id;
EXCEPTION
  WHEN unique_violation THEN
    IF v_event_key IS NOT NULL THEN
      SELECT id INTO v_id
      FROM public.notifications
      WHERE user_id = p_user_id
        AND data->>'event_key' = v_event_key
      ORDER BY created_at DESC
      LIMIT 1;
      IF v_id IS NOT NULL THEN
        RETURN v_id;
      END IF;
    END IF;
    RAISE;
END;
$$;

REVOKE ALL ON FUNCTION public.create_notification(uuid,text,text,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_notification(uuid,text,text,text,jsonb) TO authenticated;

-- ============================================================================
-- CALL LIFECYCLE: HEARTBEAT + STALE SESSION RECOVERY
-- ============================================================================

ALTER TABLE IF EXISTS public.call_sessions
  ADD COLUMN IF NOT EXISTS last_activity_at timestamptz;

UPDATE public.call_sessions
SET last_activity_at = COALESCE(last_activity_at, accepted_at, created_at, now())
WHERE last_activity_at IS NULL;

ALTER TABLE IF EXISTS public.call_sessions
  ALTER COLUMN last_activity_at SET DEFAULT now();

CREATE INDEX IF NOT EXISTS call_sessions_pair_activity_idx
ON public.call_sessions(caller_id, receiver_id, status, last_activity_at DESC);

CREATE OR REPLACE FUNCTION public.touch_call_session_status_v44()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    NEW.last_activity_at := now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS call_sessions_touch_activity_v44
ON public.call_sessions;

CREATE TRIGGER call_sessions_touch_activity_v44
BEFORE UPDATE OF status ON public.call_sessions
FOR EACH ROW
EXECUTE FUNCTION public.touch_call_session_status_v44();

CREATE OR REPLACE FUNCTION public.touch_call_activity_from_signal_v44()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.call_sessions
  SET last_activity_at = now()
  WHERE id = NEW.call_id
    AND status IN ('ringing', 'accepted');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS call_signals_touch_activity_v44
ON public.call_signals;

CREATE TRIGGER call_signals_touch_activity_v44
AFTER INSERT ON public.call_signals
FOR EACH ROW
EXECUTE FUNCTION public.touch_call_activity_from_signal_v44();

CREATE OR REPLACE FUNCTION public.heartbeat_call(p_call_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  me uuid := auth.uid();
  changed_count integer := 0;
BEGIN
  IF me IS NULL OR p_call_id IS NULL THEN
    RETURN false;
  END IF;

  UPDATE public.call_sessions
  SET last_activity_at = now()
  WHERE id = p_call_id
    AND status = 'accepted'
    AND (caller_id = me OR receiver_id = me);

  GET DIAGNOSTICS changed_count = ROW_COUNT;
  RETURN changed_count > 0;
END;
$$;

REVOKE ALL ON FUNCTION public.heartbeat_call(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.heartbeat_call(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.start_call(p_receiver_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_call_id uuid;
  v_lock_key bigint;
  v_existing record;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  IF p_receiver_id IS NULL OR p_receiver_id = v_caller_id THEN
    RAISE EXCEPTION 'INVALID_RECEIVER';
  END IF;

  v_lock_key := hashtextextended(
    least(v_caller_id::text, p_receiver_id::text) || ':' ||
    greatest(v_caller_id::text, p_receiver_id::text),
    0
  );
  PERFORM pg_advisory_xact_lock(v_lock_key);

  -- Ringing calls older than 90 seconds are dead.
  UPDATE public.call_sessions
  SET status = 'ended', ended_at = now(), last_activity_at = now()
  WHERE status = 'ringing'
    AND last_activity_at < now() - interval '90 seconds'
    AND (
      (caller_id = v_caller_id AND receiver_id = p_receiver_id)
      OR (caller_id = p_receiver_id AND receiver_id = v_caller_id)
    );

  -- Accepted calls are kept alive by the Flutter heartbeat and call signals.
  -- If neither has touched the session for five minutes, it is recoverably stale.
  UPDATE public.call_sessions
  SET status = 'ended', ended_at = now(), last_activity_at = now()
  WHERE status = 'accepted'
    AND last_activity_at < now() - interval '5 minutes'
    AND (
      (caller_id = v_caller_id AND receiver_id = p_receiver_id)
      OR (caller_id = p_receiver_id AND receiver_id = v_caller_id)
    );

  SELECT id, status, caller_id, receiver_id
  INTO v_existing
  FROM public.call_sessions
  WHERE status IN ('ringing', 'accepted')
    AND (
      (caller_id = v_caller_id AND receiver_id = p_receiver_id)
      OR (caller_id = p_receiver_id AND receiver_id = v_caller_id)
    )
  ORDER BY created_at DESC
  LIMIT 1;

  IF FOUND THEN
    IF v_existing.status = 'accepted' THEN
      RAISE EXCEPTION 'CALL_ALREADY_CONNECTED';
    END IF;

    IF v_existing.caller_id = v_caller_id THEN
      RETURN v_existing.id;
    END IF;

    RAISE EXCEPTION 'PARTNER_CALL_IN_PROGRESS';
  END IF;

  INSERT INTO public.call_sessions (
    caller_id, receiver_id, status, last_activity_at
  )
  VALUES (
    v_caller_id, p_receiver_id, 'ringing', now()
  )
  RETURNING id INTO v_call_id;

  RETURN v_call_id;
END;
$$;

REVOKE ALL ON FUNCTION public.start_call(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.start_call(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
