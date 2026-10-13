-- BESTIE: robust JSON RPCs for Truth or Dare + Memory Match
-- Run this AFTER the original 20260917_truth_or_dare_memory_match.sql.
-- The JSON return type avoids PostgREST composite-return decoding issues.

create extension if not exists pgcrypto;

create table if not exists public.memory_match_sessions (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references auth.users(id) on delete cascade,
  partner_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'playing' check (status in ('playing','completed')),
  board jsonb not null default '[]'::jsonb,
  flipped_indices jsonb not null default '[]'::jsonb,
  matched_indices jsonb not null default '[]'::jsonb,
  scores jsonb not null default '{}'::jsonb,
  turn_user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists memory_match_pair_idx on public.memory_match_sessions(created_by, partner_id, status);
alter table public.memory_match_sessions enable row level security;

drop policy if exists memory_match_sessions_select on public.memory_match_sessions;
create policy memory_match_sessions_select on public.memory_match_sessions
for select to authenticated
using (auth.uid() = created_by or auth.uid() = partner_id);

create or replace function public.bestie_is_paired_with(p_partner_id uuid)
returns boolean
language sql stable security definer set search_path=public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and paired_with = p_partner_id
  );
$$;
revoke all on function public.bestie_is_paired_with(uuid) from public;
grant execute on function public.bestie_is_paired_with(uuid) to authenticated;

create or replace function public.create_memory_match_session_json(p_partner_id uuid)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_user uuid := auth.uid();
  v_existing public.memory_match_sessions;
  v_id uuid;
  v_board jsonb;
  v_symbols text[] := array['🐶','🐱','🦊','🐼','🐸','🦄'];
  v_result jsonb;
begin
  if v_user is null then
    raise exception 'Authentication required';
  end if;

  if p_partner_id is null or p_partner_id = v_user then
    raise exception 'Invalid partner';
  end if;

  if not public.bestie_is_paired_with(p_partner_id) then
    raise exception 'Not paired with this partner';
  end if;

  select * into v_existing
  from public.memory_match_sessions
  where status = 'playing'
    and ((created_by = v_user and partner_id = p_partner_id)
      or (created_by = p_partner_id and partner_id = v_user))
  order by created_at desc
  limit 1;

  if v_existing.id is not null then
    select to_jsonb(v_existing) into v_result;
    return v_result;
  end if;

  select jsonb_agg(to_jsonb(x))
  into v_board
  from (
    select unnest(v_symbols || v_symbols) as x
    order by random()
  ) q;

  insert into public.memory_match_sessions (
    created_by,
    partner_id,
    board,
    flipped_indices,
    matched_indices,
    scores,
    turn_user_id
  )
  values (
    v_user,
    p_partner_id,
    coalesce(v_board, '[]'::jsonb),
    '[]'::jsonb,
    '[]'::jsonb,
    jsonb_build_object(v_user::text, 0, p_partner_id::text, 0),
    v_user
  )
  returning id into v_id;

  select to_jsonb(s) into v_result
  from public.memory_match_sessions s
  where s.id = v_id;

  return v_result;
end;
$$;

create or replace function public.get_active_memory_match_session_json(p_partner_id uuid)
returns jsonb
language sql security definer set search_path=public
as $$
  select coalesce(to_jsonb(s), '{}'::jsonb)
  from public.memory_match_sessions s
  where s.status = 'playing'
    and ((s.created_by = auth.uid() and s.partner_id = p_partner_id)
      or (s.created_by = p_partner_id and s.partner_id = auth.uid()))
  order by s.created_at desc
  limit 1;
$$;

create or replace function public.memory_match_flip_json(p_session_id uuid, p_index integer)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  s public.memory_match_sessions;
  v_flipped int[];
  v_result jsonb;
begin
  select * into s
  from public.memory_match_sessions
  where id = p_session_id
    and status = 'playing'
    and (created_by = auth.uid() or partner_id = auth.uid())
  for update;

  if s.id is null then raise exception 'Memory Match session not found'; end if;
  if s.turn_user_id <> auth.uid() then raise exception 'Not your turn'; end if;
  if p_index < 0 or p_index >= jsonb_array_length(s.board) then raise exception 'Invalid card'; end if;

  v_flipped := coalesce(
    array(select jsonb_array_elements_text(s.flipped_indices)::int),
    '{}'::int[]
  );

  if p_index = any(v_flipped)
     or p_index = any(coalesce(array(select jsonb_array_elements_text(s.matched_indices)::int), '{}'::int[]))
     or coalesce(array_length(v_flipped, 1), 0) >= 2 then
    raise exception 'Card cannot be selected';
  end if;

  v_flipped := array_append(v_flipped, p_index);

  update public.memory_match_sessions
  set flipped_indices = to_jsonb(v_flipped), updated_at = now()
  where id = s.id;

  select to_jsonb(x) into v_result
  from public.memory_match_sessions x
  where x.id = s.id;

  return v_result;
end;
$$;

create or replace function public.memory_match_resolve_turn_json(p_session_id uuid)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  s public.memory_match_sessions;
  v_f int[];
  v_m int[];
  v_board text[];
  v_scores jsonb;
  v_a int;
  v_b int;
  v_same boolean;
  v_next uuid;
  v_result jsonb;
begin
  select * into s
  from public.memory_match_sessions
  where id = p_session_id
    and status = 'playing'
    and (created_by = auth.uid() or partner_id = auth.uid())
  for update;

  if s.id is null then raise exception 'Memory Match session not found'; end if;
  if s.turn_user_id <> auth.uid() then raise exception 'Not your turn'; end if;

  v_f := coalesce(array(select jsonb_array_elements_text(s.flipped_indices)::int), '{}'::int[]);
  if coalesce(array_length(v_f, 1), 0) <> 2 then
    return to_jsonb(s);
  end if;

  v_m := coalesce(array(select jsonb_array_elements_text(s.matched_indices)::int), '{}'::int[]);
  v_board := array(select jsonb_array_elements_text(s.board));
  v_a := v_f[1];
  v_b := v_f[2];
  v_same := v_board[v_a + 1] = v_board[v_b + 1];
  v_scores := s.scores;

  if v_same then
    v_m := array_append(array_append(v_m, v_a), v_b);
    v_scores := jsonb_set(
      v_scores,
      array[auth.uid()::text],
      to_jsonb(coalesce((v_scores ->> auth.uid()::text)::int, 0) + 1),
      true
    );
  else
    v_next := case
      when s.turn_user_id = s.created_by then s.partner_id
      else s.created_by
    end;
  end if;

  if coalesce(array_length(v_m, 1), 0) >= array_length(v_board, 1) then
    update public.memory_match_sessions
    set status = 'completed',
        flipped_indices = '[]'::jsonb,
        matched_indices = to_jsonb(v_m),
        scores = v_scores,
        updated_at = now()
    where id = s.id;
  else
    if v_same then
      v_next := s.turn_user_id;
    end if;

    update public.memory_match_sessions
    set flipped_indices = '[]'::jsonb,
        matched_indices = to_jsonb(v_m),
        scores = v_scores,
        turn_user_id = v_next,
        updated_at = now()
    where id = s.id;
  end if;

  select to_jsonb(x) into v_result
  from public.memory_match_sessions x
  where x.id = s.id;

  return v_result;
end;
$$;

-- Truth or Dare JSON wrappers. They call the existing validated functions.
create or replace function public.create_truth_or_dare_session_json(p_partner_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r public.truth_or_dare_sessions;
begin
  r := public.create_truth_or_dare_session(p_partner_id);
  return to_jsonb(r);
end; $$;

create or replace function public.get_active_truth_or_dare_session_json(p_partner_id uuid)
returns jsonb language sql security definer set search_path=public as $$
  select coalesce(to_jsonb(s), '{}'::jsonb)
  from public.truth_or_dare_sessions s
  where s.status='playing'
    and ((s.created_by=auth.uid() and s.partner_id=p_partner_id)
      or (s.created_by=p_partner_id and s.partner_id=auth.uid()))
  order by s.created_at desc
  limit 1;
$$;

create or replace function public.start_truth_or_dare_round_json(p_session_id uuid,p_mode text,p_prompt_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r public.truth_or_dare_sessions;
begin
  r := public.start_truth_or_dare_round(p_session_id,p_mode,p_prompt_id);
  return to_jsonb(r);
end; $$;

create or replace function public.complete_truth_or_dare_round_json(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r public.truth_or_dare_sessions;
begin
  r := public.complete_truth_or_dare_round(p_session_id);
  return to_jsonb(r);
end; $$;

revoke all on function public.create_memory_match_session_json(uuid) from public;
grant execute on function public.create_memory_match_session_json(uuid) to authenticated;
revoke all on function public.get_active_memory_match_session_json(uuid) from public;
grant execute on function public.get_active_memory_match_session_json(uuid) to authenticated;
revoke all on function public.memory_match_flip_json(uuid,integer) from public;
grant execute on function public.memory_match_flip_json(uuid,integer) to authenticated;
revoke all on function public.memory_match_resolve_turn_json(uuid) from public;
grant execute on function public.memory_match_resolve_turn_json(uuid) to authenticated;
revoke all on function public.create_truth_or_dare_session_json(uuid) from public;
grant execute on function public.create_truth_or_dare_session_json(uuid) to authenticated;
revoke all on function public.get_active_truth_or_dare_session_json(uuid) from public;
grant execute on function public.get_active_truth_or_dare_session_json(uuid) to authenticated;
revoke all on function public.start_truth_or_dare_round_json(uuid,text,uuid) from public;
grant execute on function public.start_truth_or_dare_round_json(uuid,text,uuid) to authenticated;
revoke all on function public.complete_truth_or_dare_round_json(uuid) from public;
grant execute on function public.complete_truth_or_dare_round_json(uuid) to authenticated;

alter table public.memory_match_sessions replica identity full;
do $$ begin
  alter publication supabase_realtime add table public.memory_match_sessions;
exception when duplicate_object then null;
end $$;
