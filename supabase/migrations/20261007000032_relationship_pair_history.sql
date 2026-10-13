-- BESTIE 32 — PERMANENT PARTNER HISTORY
-- IMPORTANT: A relationship is identified by the two users, not by a
-- temporary matching session. Ending a match never deletes shared history.
-- Re-matching the same person reuses the same relationship_pairs row.

create extension if not exists pgcrypto;

create table if not exists public.relationship_pairs (
  id uuid primary key default gen_random_uuid(),
  user_a_id uuid not null references auth.users(id) on delete cascade,
  user_b_id uuid not null references auth.users(id) on delete cascade,
  first_paired_at timestamptz not null default now(),
  last_paired_at timestamptz not null default now(),
  ended_at timestamptz,
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint relationship_pairs_not_self check (user_a_id <> user_b_id),
  constraint relationship_pairs_canonical check (user_a_id < user_b_id),
  constraint relationship_pairs_unique_pair unique (user_a_id, user_b_id)
);

create index if not exists relationship_pairs_user_a_idx
  on public.relationship_pairs(user_a_id);
create index if not exists relationship_pairs_user_b_idx
  on public.relationship_pairs(user_b_id);
create index if not exists relationship_pairs_active_idx
  on public.relationship_pairs(is_active) where is_active;

alter table public.relationship_pairs enable row level security;

drop policy if exists relationship_pairs_select_participant
  on public.relationship_pairs;

create policy relationship_pairs_select_participant
on public.relationship_pairs
for select to authenticated
using (auth.uid() = user_a_id or auth.uid() = user_b_id);

-- ---------------------------------------------------------------------------
-- Create/find the permanent pair row WITHOUT changing its active state.
-- This is used by historical backfill and by the pairing RPC.
-- ---------------------------------------------------------------------------
create or replace function public.ensure_relationship_pair(
  p_user_id uuid,
  p_partner_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_a uuid;
  v_b uuid;
  v_id uuid;
begin
  if p_user_id is null
     or p_partner_id is null
     or p_user_id = p_partner_id then
    raise exception 'Invalid relationship pair';
  end if;

  v_a := least(p_user_id, p_partner_id);
  v_b := greatest(p_user_id, p_partner_id);

  insert into public.relationship_pairs(
    user_a_id,
    user_b_id,
    first_paired_at,
    last_paired_at,
    ended_at,
    is_active
  )
  values (
    v_a,
    v_b,
    now(),
    now(),
    null,
    false
  )
  on conflict (user_a_id, user_b_id)
  do nothing;

  select id into v_id
  from public.relationship_pairs
  where user_a_id = v_a
    and user_b_id = v_b;

  return v_id;
end;
$$;

revoke all on function public.ensure_relationship_pair(uuid,uuid) from public;
grant execute on function public.ensure_relationship_pair(uuid,uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Activate an existing pair when the two users actually match.
-- ---------------------------------------------------------------------------
create or replace function public.activate_relationship_pair(
  p_user_id uuid,
  p_partner_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  v_id := public.ensure_relationship_pair(p_user_id, p_partner_id);

  update public.relationship_pairs
  set is_active = true,
      last_paired_at = now(),
      ended_at = null,
      updated_at = now()
  where id = v_id;

  return v_id;
end;
$$;

revoke all on function public.activate_relationship_pair(uuid,uuid) from public;
grant execute on function public.activate_relationship_pair(uuid,uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Public RPC: current user's permanent pair ID for a specific partner.
-- Works even when that pair is currently inactive.
-- ---------------------------------------------------------------------------
create or replace function public.get_relationship_pair_id(p_partner_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id
  from public.relationship_pairs
  where user_a_id = least(auth.uid(), p_partner_id)
    and user_b_id = greatest(auth.uid(), p_partner_id)
  limit 1;
$$;

revoke all on function public.get_relationship_pair_id(uuid) from public;
grant execute on function public.get_relationship_pair_id(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Pairing RPC.
-- Re-matching the same person reactivates the SAME relationship row.
-- ---------------------------------------------------------------------------
drop function if exists public.pair_users_by_code(text);

create function public.pair_users_by_code(p_pair_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_partner uuid;
  v_relationship uuid;
  v_current uuid;
begin
  if v_user is null then
    raise exception 'Authentication required';
  end if;

  if nullif(trim(p_pair_code), '') is null then
    raise exception 'Pair code is required';
  end if;

  select paired_with
  into v_current
  from public.profiles
  where id = v_user
  for update;

  if v_current is not null then
    raise exception 'You are already paired';
  end if;

  select id
  into v_partner
  from public.profiles
  where pair_code = trim(p_pair_code)
    and id <> v_user
  for update;

  if v_partner is null then
    raise exception 'Pair code not found';
  end if;

  select paired_with
  into v_current
  from public.profiles
  where id = v_partner;

  if v_current is not null and v_current <> v_user then
    raise exception 'This user is already paired';
  end if;

  v_relationship := public.activate_relationship_pair(v_user, v_partner);

  update public.profiles
  set paired_with = v_partner,
      updated_at = now()
  where id = v_user;

  update public.profiles
  set paired_with = v_user,
      updated_at = now()
  where id = v_partner;

  return v_relationship;
end;
$$;

revoke all on function public.pair_users_by_code(text) from public;
grant execute on function public.pair_users_by_code(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Unpair: only active relationship state changes.
-- NO shared row or storage object is deleted.
-- ---------------------------------------------------------------------------
drop function if exists public.unpair_current_user();

create function public.unpair_current_user()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_partner uuid;
  v_relationship uuid;
begin
  if v_user is null then
    raise exception 'Authentication required';
  end if;

  select paired_with
  into v_partner
  from public.profiles
  where id = v_user
  for update;

  if v_partner is null then
    return null;
  end if;

  select id
  into v_relationship
  from public.relationship_pairs
  where user_a_id = least(v_user, v_partner)
    and user_b_id = greatest(v_user, v_partner)
  for update;

  if v_relationship is not null then
    update public.relationship_pairs
    set is_active = false,
        ended_at = now(),
        updated_at = now()
    where id = v_relationship;
  end if;

  update public.profiles
  set paired_with = null,
      updated_at = now()
  where id in (v_user, v_partner);

  return v_partner;
end;
$$;

revoke all on function public.unpair_current_user() from public;
grant execute on function public.unpair_current_user() to authenticated;

-- ---------------------------------------------------------------------------
-- Pair-scoped ROOT tables.
--
-- Child rows such as call_signals, game_players, game_rounds and game_answers
-- inherit their relationship from their parent session. We intentionally do
-- NOT require relationship_id on those child tables, which makes this
-- migration safe for older installations whose child schemas differ.
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
  tables text[] := array[
    'messages',
    'todos',
    'interactions',
    'map_selections',
    'call_sessions',
    'game_sessions',
    'game_word_sessions',
    'memory_match_sessions',
    'name_city_animal_games',
    'hall_of_fame_photos',
    'relationship_daily_activity',
    'love_letters',
    'places',
    'shared_pets'
  ];
begin
  foreach t in array tables loop
    if to_regclass('public.' || t) is not null then
      execute format(
        'alter table public.%I add column if not exists relationship_id uuid references public.relationship_pairs(id) on delete set null',
        t
      );
      execute format(
        'create index if not exists %I on public.%I(relationship_id)',
        t || '_relationship_id_idx',
        t
      );
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Build relationship_pairs from EXISTING historical data.
-- This is the part the previous migration was missing: relationship_pairs
-- cannot be empty if old Alex/Yoso history already exists.
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
  cols record;
  tables text[] := array[
    'messages',
    'todos',
    'interactions',
    'map_selections',
    'call_sessions',
    'game_sessions',
    'game_word_sessions',
    'memory_match_sessions',
    'name_city_animal_games',
    'hall_of_fame_photos',
    'relationship_daily_activity',
    'love_letters',
    'places',
    'shared_pets'
  ];
begin
  foreach t in array tables loop
    if to_regclass('public.' || t) is null then
      continue;
    end if;

    -- sender/receiver
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name=t and column_name='sender_id'
    ) and exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name=t and column_name='receiver_id'
    ) then
      execute format(
        'insert into public.relationship_pairs(user_a_id,user_b_id,first_paired_at,last_paired_at)
         select least(sender_id,receiver_id), greatest(sender_id,receiver_id),
                coalesce(min(created_at),now()), coalesce(max(created_at),now())
         from public.%I
         where sender_id is not null and receiver_id is not null
           and sender_id <> receiver_id
         group by least(sender_id,receiver_id), greatest(sender_id,receiver_id)
         on conflict (user_a_id,user_b_id) do nothing',
        t
      );
    end if;

    -- user/partner
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name=t and column_name='user_id'
    ) and exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name=t and column_name='partner_id'
    ) then
      execute format(
        'insert into public.relationship_pairs(user_a_id,user_b_id,first_paired_at,last_paired_at)
         select least(user_id,partner_id), greatest(user_id,partner_id),
                coalesce(min(created_at),now()), coalesce(max(created_at),now())
         from public.%I
         where user_id is not null and partner_id is not null
           and user_id <> partner_id
         group by least(user_id,partner_id), greatest(user_id,partner_id)
         on conflict (user_a_id,user_b_id) do nothing',
        t
      );
    end if;

    -- created_by/partner
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name=t and column_name='created_by'
    ) and exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name=t and column_name='partner_id'
    ) then
      execute format(
        'insert into public.relationship_pairs(user_a_id,user_b_id,first_paired_at,last_paired_at)
         select least(created_by,partner_id), greatest(created_by,partner_id),
                coalesce(min(created_at),now()), coalesce(max(created_at),now())
         from public.%I
         where created_by is not null and partner_id is not null
           and created_by <> partner_id
         group by least(created_by,partner_id), greatest(created_by,partner_id)
         on conflict (user_a_id,user_b_id) do nothing',
        t
      );
    end if;

    -- caller/receiver
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name=t and column_name='caller_id'
    ) and exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name=t and column_name='receiver_id'
    ) then
      execute format(
        'insert into public.relationship_pairs(user_a_id,user_b_id,first_paired_at,last_paired_at)
         select least(caller_id,receiver_id), greatest(caller_id,receiver_id),
                coalesce(min(created_at),now()), coalesce(max(created_at),now())
         from public.%I
         where caller_id is not null and receiver_id is not null
           and caller_id <> receiver_id
         group by least(caller_id,receiver_id), greatest(caller_id,receiver_id)
         on conflict (user_a_id,user_b_id) do nothing',
        t
      );
    end if;

    -- owner/partner
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name=t and column_name='owner_id'
    ) and exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name=t and column_name='partner_id'
    ) then
      execute format(
        'insert into public.relationship_pairs(user_a_id,user_b_id,first_paired_at,last_paired_at)
         select least(owner_id,partner_id), greatest(owner_id,partner_id),
                coalesce(min(created_at),now()), coalesce(max(created_at),now())
         from public.%I
         where owner_id is not null and partner_id is not null
           and owner_id <> partner_id
         group by least(owner_id,partner_id), greatest(owner_id,partner_id)
         on conflict (user_a_id,user_b_id) do nothing',
        t
      );
    end if;

    -- shared_pets: user_a/user_b
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name=t and column_name='user_a_id'
    ) and exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name=t and column_name='user_b_id'
    ) then
      execute format(
        'insert into public.relationship_pairs(user_a_id,user_b_id,first_paired_at,last_paired_at)
         select least(user_a_id,user_b_id), greatest(user_a_id,user_b_id),
                coalesce(min(updated_at),now()), coalesce(max(updated_at),now())
         from public.%I
         where user_a_id is not null and user_b_id is not null
           and user_a_id <> user_b_id
         group by least(user_a_id,user_b_id), greatest(user_a_id,user_b_id)
         on conflict (user_a_id,user_b_id) do nothing',
        t
      );
    end if;
  end loop;

  -- Some older game_sessions schemas do not store partner_id. In that
  -- installation the durable participant set is game_players(session_id,user_id).
  if to_regclass('public.game_players') is not null
     and to_regclass('public.game_sessions') is not null
     and exists(select 1 from information_schema.columns where table_schema='public' and table_name='game_players' and column_name='session_id')
     and exists(select 1 from information_schema.columns where table_schema='public' and table_name='game_players' and column_name='user_id') then
    begin
      execute $sql$
        insert into public.relationship_pairs(user_a_id,user_b_id,first_paired_at,last_paired_at)
        select
          least(gp.user_id, gp2.user_id),
          greatest(gp.user_id, gp2.user_id),
          now(), now()
        from public.game_players gp
        join public.game_players gp2
          on gp2.session_id = gp.session_id
         and gp2.user_id <> gp.user_id
        group by gp.session_id, least(gp.user_id,gp2.user_id), greatest(gp.user_id,gp2.user_id)
        on conflict (user_a_id,user_b_id) do nothing
      $sql$;
    exception when undefined_column or undefined_table then
      null;
    end;
  end if;

  -- The currently paired profiles MUST have an active relationship row.
  insert into public.relationship_pairs(
    user_a_id,user_b_id,first_paired_at,last_paired_at,is_active,ended_at
  )
  select
    least(p.id,p.paired_with),
    greatest(p.id,p.paired_with),
    now(),
    now(),
    true,
    null
  from public.profiles p
  where p.paired_with is not null
  group by least(p.id,p.paired_with), greatest(p.id,p.paired_with)
  on conflict (user_a_id,user_b_id)
  do update set
    is_active=true,
    ended_at=null,
    last_paired_at=now(),
    updated_at=now();
end $$;

-- ---------------------------------------------------------------------------
-- Backfill relationship_id on ROOT tables with directly stored participants.
-- All statements are guarded by information_schema so an older schema cannot
-- fail because one optional column (e.g. NCA answer.session_id) is absent.
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.messages') is not null
     and exists(select 1 from information_schema.columns where table_schema='public' and table_name='messages' and column_name='sender_id')
     and exists(select 1 from information_schema.columns where table_schema='public' and table_name='messages' and column_name='receiver_id') then
    update public.messages m
    set relationship_id = rp.id
    from public.relationship_pairs rp
    where m.relationship_id is null
      and rp.user_a_id = least(m.sender_id,m.receiver_id)
      and rp.user_b_id = greatest(m.sender_id,m.receiver_id);
  end if;

  if to_regclass('public.todos') is not null then
    update public.todos x
    set relationship_id = rp.id
    from public.relationship_pairs rp
    where x.relationship_id is null
      and rp.user_a_id = least(x.user_id,x.partner_id)
      and rp.user_b_id = greatest(x.user_id,x.partner_id);
  end if;

  if to_regclass('public.interactions') is not null then
    update public.interactions x
    set relationship_id = rp.id
    from public.relationship_pairs rp
    where x.relationship_id is null
      and rp.user_a_id = least(x.sender_id,x.receiver_id)
      and rp.user_b_id = greatest(x.sender_id,x.receiver_id);
  end if;

  if to_regclass('public.map_selections') is not null then
    update public.map_selections x
    set relationship_id = rp.id
    from public.relationship_pairs rp
    where x.relationship_id is null
      and rp.user_a_id = least(x.user_id,x.partner_id)
      and rp.user_b_id = greatest(x.user_id,x.partner_id);
  end if;

  if to_regclass('public.call_sessions') is not null then
    update public.call_sessions x
    set relationship_id = rp.id
    from public.relationship_pairs rp
    where x.relationship_id is null
      and rp.user_a_id = least(x.caller_id,x.receiver_id)
      and rp.user_b_id = greatest(x.caller_id,x.receiver_id);
  end if;

  if to_regclass('public.game_sessions') is not null
     and exists(select 1 from information_schema.columns where table_schema='public' and table_name='game_sessions' and column_name='created_by')
     and exists(select 1 from information_schema.columns where table_schema='public' and table_name='game_sessions' and column_name='partner_id') then
    update public.game_sessions x
    set relationship_id = rp.id
    from public.relationship_pairs rp
    where x.relationship_id is null
      and rp.user_a_id = least(x.created_by,x.partner_id)
      and rp.user_b_id = greatest(x.created_by,x.partner_id);
  end if;

  -- Older game_sessions may have only an id and game_players.
  if to_regclass('public.game_sessions') is not null
     and to_regclass('public.game_players') is not null
     and exists(select 1 from information_schema.columns where table_schema='public' and table_name='game_players' and column_name='session_id')
     and exists(select 1 from information_schema.columns where table_schema='public' and table_name='game_players' and column_name='user_id') then
    begin
      execute $sql$
        update public.game_sessions gs
        set relationship_id = rp.id
        from (
          select gp.session_id,
                 least(gp.user_id,gp2.user_id) as user_a_id,
                 greatest(gp.user_id,gp2.user_id) as user_b_id
          from public.game_players gp
          join public.game_players gp2
            on gp2.session_id = gp.session_id
           and gp2.user_id <> gp.user_id
          group by gp.session_id, least(gp.user_id,gp2.user_id), greatest(gp.user_id,gp2.user_id)
        ) pairs
        join public.relationship_pairs rp
          on rp.user_a_id = pairs.user_a_id
         and rp.user_b_id = pairs.user_b_id
        where gs.relationship_id is null
          and gs.id = pairs.session_id
      $sql$;
    exception when undefined_column or undefined_table then
      null;
    end;
  end if;

  if to_regclass('public.game_word_sessions') is not null
     and exists(select 1 from information_schema.columns where table_schema='public' and table_name='game_word_sessions' and column_name='created_by')
     and exists(select 1 from information_schema.columns where table_schema='public' and table_name='game_word_sessions' and column_name='partner_id') then
    update public.game_word_sessions x
    set relationship_id = rp.id
    from public.relationship_pairs rp
    where x.relationship_id is null
      and rp.user_a_id = least(x.created_by,x.partner_id)
      and rp.user_b_id = greatest(x.created_by,x.partner_id);
  end if;

  if to_regclass('public.memory_match_sessions') is not null then
    update public.memory_match_sessions x
    set relationship_id = rp.id
    from public.relationship_pairs rp
    where x.relationship_id is null
      and rp.user_a_id = least(x.created_by,x.partner_id)
      and rp.user_b_id = greatest(x.created_by,x.partner_id);
  end if;

  if to_regclass('public.name_city_animal_games') is not null then
    update public.name_city_animal_games x
    set relationship_id = rp.id
    from public.relationship_pairs rp
    where x.relationship_id is null
      and rp.user_a_id = least(x.created_by,x.partner_id)
      and rp.user_b_id = greatest(x.created_by,x.partner_id);
  end if;

  if to_regclass('public.hall_of_fame_photos') is not null then
    update public.hall_of_fame_photos x
    set relationship_id = rp.id
    from public.relationship_pairs rp
    where x.relationship_id is null
      and x.partner_id is not null
      and rp.user_a_id = least(x.owner_id,x.partner_id)
      and rp.user_b_id = greatest(x.owner_id,x.partner_id);
  end if;

  if to_regclass('public.relationship_daily_activity') is not null then
    update public.relationship_daily_activity x
    set relationship_id = rp.id
    from public.relationship_pairs rp
    where x.relationship_id is null
      and rp.user_a_id = least(x.user_id,x.partner_id)
      and rp.user_b_id = greatest(x.user_id,x.partner_id);
  end if;

  if to_regclass('public.love_letters') is not null then
    update public.love_letters x
    set relationship_id = rp.id
    from public.relationship_pairs rp
    where x.relationship_id is null
      and rp.user_a_id = least(x.sender_id,x.receiver_id)
      and rp.user_b_id = greatest(x.sender_id,x.receiver_id);
  end if;

  if to_regclass('public.places') is not null then
    update public.places x
    set relationship_id = rp.id
    from public.relationship_pairs rp
    where x.relationship_id is null
      and rp.user_a_id = least(x.user_id,x.partner_id)
      and rp.user_b_id = greatest(x.user_id,x.partner_id);
  end if;

  if to_regclass('public.shared_pets') is not null
     and exists(select 1 from information_schema.columns where table_schema='public' and table_name='shared_pets' and column_name='user_a_id')
     and exists(select 1 from information_schema.columns where table_schema='public' and table_name='shared_pets' and column_name='user_b_id') then
    update public.shared_pets x
    set relationship_id = rp.id
    from public.relationship_pairs rp
    where x.relationship_id is null
      and rp.user_a_id = least(x.user_a_id,x.user_b_id)
      and rp.user_b_id = greatest(x.user_a_id,x.user_b_id);
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Generic future-row resolver.
-- IMPORTANT: It only uses an EXISTING relationship row. It never turns an
-- inactive historical relationship back on just because an insert occurs.
-- ---------------------------------------------------------------------------
create or replace function public.bestie_resolve_relationship_id(
  p_user_id uuid,
  p_partner_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_user_id is null or p_partner_id is null or p_user_id = p_partner_id then
    return null;
  end if;

  select id into v_id
  from public.relationship_pairs
  where user_a_id = least(p_user_id,p_partner_id)
    and user_b_id = greatest(p_user_id,p_partner_id);

  return v_id;
end;
$$;

revoke all on function public.bestie_resolve_relationship_id(uuid,uuid) from public;
grant execute on function public.bestie_resolve_relationship_id(uuid,uuid) to authenticated;

create or replace function public.bestie_assign_relationship_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  j jsonb := to_jsonb(new);
  v_a uuid;
  v_b uuid;
  v_rid uuid;
  v_session uuid;
begin
  if new.relationship_id is not null then
    return new;
  end if;

  -- Direct pair shapes.
  if j ? 'sender_id' and j ? 'receiver_id' then
    v_a := nullif(j->>'sender_id','')::uuid;
    v_b := nullif(j->>'receiver_id','')::uuid;

  elsif j ? 'user_id' and j ? 'partner_id' then
    v_a := nullif(j->>'user_id','')::uuid;
    v_b := nullif(j->>'partner_id','')::uuid;

  elsif j ? 'created_by' and j ? 'partner_id' then
    v_a := nullif(j->>'created_by','')::uuid;
    v_b := nullif(j->>'partner_id','')::uuid;

  elsif j ? 'caller_id' and j ? 'receiver_id' then
    v_a := nullif(j->>'caller_id','')::uuid;
    v_b := nullif(j->>'receiver_id','')::uuid;

  elsif j ? 'owner_id' and j ? 'partner_id' then
    v_a := nullif(j->>'owner_id','')::uuid;
    v_b := nullif(j->>'partner_id','')::uuid;

  elsif j ? 'user_a_id' and j ? 'user_b_id' then
    v_a := nullif(j->>'user_a_id','')::uuid;
    v_b := nullif(j->>'user_b_id','')::uuid;

  -- Child rows inherit from their parent session.
  elsif j ? 'call_id' then
    select relationship_id into v_rid
    from public.call_sessions
    where id = nullif(j->>'call_id','')::uuid;
    if v_rid is not null then
      new.relationship_id := v_rid;
      return new;
    end if;

  elsif j ? 'session_id' then
    v_session := nullif(j->>'session_id','')::uuid;

    if to_regclass('public.name_city_animal_games') is not null then
      begin
        select relationship_id into v_rid
        from public.name_city_animal_games
        where session_id = v_session;
      exception when undefined_column or undefined_table then
        v_rid := null;
      end;
      if v_rid is not null then
        new.relationship_id := v_rid;
        return new;
      end if;
    end if;

    if to_regclass('public.game_word_sessions') is not null then
      begin
        select relationship_id into v_rid
        from public.game_word_sessions
        where session_id = v_session;
      exception when undefined_column or undefined_table then
        v_rid := null;
      end;
      if v_rid is not null then
        new.relationship_id := v_rid;
        return new;
      end if;
    end if;

    if to_regclass('public.game_sessions') is not null then
      begin
        select relationship_id into v_rid
        from public.game_sessions
        where id = v_session;
      exception when undefined_column or undefined_table then
        v_rid := null;
      end;
      if v_rid is not null then
        new.relationship_id := v_rid;
        return new;
      end if;
    end if;

    if to_regclass('public.memory_match_sessions') is not null then
      begin
        select relationship_id into v_rid
        from public.memory_match_sessions
        where id = v_session;
      exception when undefined_column or undefined_table then
        v_rid := null;
      end;
      if v_rid is not null then
        new.relationship_id := v_rid;
        return new;
      end if;
    end if;
  end if;

  if v_a is not null and v_b is not null and v_a <> v_b then
    v_rid := public.bestie_resolve_relationship_id(v_a,v_b);
    if v_rid is not null then
      new.relationship_id := v_rid;
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.bestie_assign_relationship_id() from public;
grant execute on function public.bestie_assign_relationship_id() to authenticated;

do $$
declare
  t text;
  tables text[] := array[
    'messages',
    'todos',
    'interactions',
    'map_selections',
    'call_sessions',
    'game_sessions',
    'game_word_sessions',
    'memory_match_sessions',
    'name_city_animal_games',
    'hall_of_fame_photos',
    'relationship_daily_activity',
    'love_letters',
    'places',
    'shared_pets'
  ];
begin
  foreach t in array tables loop
    if to_regclass('public.' || t) is not null then
      execute format(
        'drop trigger if exists bestie_relationship_id_%I on public.%I',
        t,t
      );
      execute format(
        'create trigger bestie_relationship_id_%I
         before insert on public.%I
         for each row execute function public.bestie_assign_relationship_id()',
        t,t
      );
    end if;
  end loop;
end $$;

-- Historical map data must remain readable after unpairing.
do $$
begin
  if to_regclass('public.map_selections') is not null then
    execute 'drop policy if exists map_select_pair on public.map_selections';
    execute $policy$
      create policy map_select_pair on public.map_selections
      for select to authenticated
      using (
        auth.uid() = user_id
        or auth.uid() = partner_id
        or exists (
          select 1
          from public.relationship_pairs rp
          where rp.id = map_selections.relationship_id
            and (auth.uid() = rp.user_a_id or auth.uid() = rp.user_b_id)
        )
      )
    $policy$;
  end if;
end $$;

notify pgrst, 'reload schema';
