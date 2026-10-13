-- BESTIE call lifecycle reconciliation.
-- Prevents stale ringing rows from permanently blocking new calls and makes
-- call creation atomic for one caller/receiver pair.

-- Existing installations may already have call_sessions without an id default.
-- start_call intentionally omits id so PostgreSQL must generate it here.
alter table public.call_sessions alter column id set default gen_random_uuid();

create or replace function public.start_call(p_receiver_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id uuid := auth.uid();
  v_call_id uuid;
  v_lock_key bigint;
  v_existing record;
begin
  if v_caller_id is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if p_receiver_id is null or p_receiver_id = v_caller_id then
    raise exception 'INVALID_RECEIVER';
  end if;

  -- Serialize calls for this exact pair. This closes the read-then-insert race
  -- caused by two rapid taps or two devices starting calls simultaneously.
  v_lock_key := hashtextextended(
    least(v_caller_id::text, p_receiver_id::text) || ':' ||
    greatest(v_caller_id::text, p_receiver_id::text),
    0
  );
  perform pg_advisory_xact_lock(v_lock_key);

  -- A crashed process can leave ringing forever. Ringing older than 90 seconds
  -- is no longer considered an incoming call.
  update public.call_sessions
     set status = 'ended', ended_at = now()
   where status = 'ringing'
     and created_at < now() - interval '90 seconds'
     and (caller_id in (v_caller_id, p_receiver_id)
       or receiver_id in (v_caller_id, p_receiver_id));

  select id, status, caller_id, receiver_id
    into v_existing
    from public.call_sessions
   where status in ('ringing', 'accepted')
     and ((caller_id = v_caller_id and receiver_id = p_receiver_id)
       or (caller_id = p_receiver_id and receiver_id = v_caller_id))
   order by created_at desc
   limit 1;

  if found then
    if v_existing.status = 'accepted' then
      raise exception 'CALL_ALREADY_CONNECTED';
    end if;

    if v_existing.caller_id = v_caller_id then
      return v_existing.id;
    end if;

    raise exception 'PARTNER_CALL_IN_PROGRESS';
  end if;

  insert into public.call_sessions (caller_id, receiver_id, status)
  values (v_caller_id, p_receiver_id, 'ringing')
  returning id into v_call_id;

  return v_call_id;
end;
$$;

revoke all on function public.start_call(uuid) from public;
grant execute on function public.start_call(uuid) to authenticated;
