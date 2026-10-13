-- BESTIE notification + permanent partner relationship hardening
-- 2026-10-06
--
-- Goals:
-- 1) A user pair has one permanent relationship identity.
-- 2) Ending a pairing never deletes relationship data.
-- 3) Re-pairing with the same person reactivates the same relationship.
-- 4) Ending a pairing creates a localized notification for the partner.
-- 5) Existing pair_users_by_code implementations are supported by a trigger.

create extension if not exists pgcrypto;

create table if not exists public.relationship_pairs (
  id uuid primary key default gen_random_uuid(),
  user_a_id uuid not null references public.profiles(id) on delete cascade,
  user_b_id uuid not null references public.profiles(id) on delete cascade,
  first_paired_at timestamptz not null default now(),
  last_paired_at timestamptz not null default now(),
  is_active boolean not null default true,
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint relationship_pairs_distinct_users check (user_a_id <> user_b_id),
  constraint relationship_pairs_canonical_users check (user_a_id < user_b_id),
  constraint relationship_pairs_users_unique unique (user_a_id, user_b_id)
);

alter table public.relationship_pairs add column if not exists first_paired_at timestamptz;
alter table public.relationship_pairs add column if not exists last_paired_at timestamptz;
alter table public.relationship_pairs add column if not exists is_active boolean;
alter table public.relationship_pairs add column if not exists ended_at timestamptz;
alter table public.relationship_pairs add column if not exists created_at timestamptz;
alter table public.relationship_pairs add column if not exists updated_at timestamptz;

update public.relationship_pairs
set first_paired_at = coalesce(first_paired_at, created_at, now()),
    last_paired_at = coalesce(last_paired_at, created_at, now()),
    is_active = coalesce(is_active, false),
    created_at = coalesce(created_at, now()),
    updated_at = coalesce(updated_at, now());

alter table public.relationship_pairs
  alter column first_paired_at set default now(),
  alter column last_paired_at set default now(),
  alter column is_active set default false,
  alter column created_at set default now(),
  alter column updated_at set default now();

create unique index if not exists relationship_pairs_users_uidx
  on public.relationship_pairs(user_a_id, user_b_id);

create unique index if not exists relationship_pairs_one_active_uidx
  on public.relationship_pairs(user_a_id, user_b_id)
  where is_active;

alter table public.relationship_pairs enable row level security;

drop policy if exists relationship_pairs_select_own on public.relationship_pairs;
create policy relationship_pairs_select_own
on public.relationship_pairs for select to authenticated
using (auth.uid() = user_a_id or auth.uid() = user_b_id);

-- Seed all currently active pairs. DISTINCT/GROUP BY is critical because
-- profiles stores the relationship in both directions.
do $$
begin
  insert into public.relationship_pairs(
    user_a_id,user_b_id,first_paired_at,last_paired_at,is_active,ended_at
  )
  select
    least(p.id,p.paired_with),
    greatest(p.id,p.paired_with),
    now(),now(),true,null
  from public.profiles p
  where p.paired_with is not null
  group by least(p.id,p.paired_with), greatest(p.id,p.paired_with)
  on conflict (user_a_id,user_b_id)
  do update set
    is_active=true,
    ended_at=null,
    last_paired_at=now(),
    updated_at=now();
exception
  when others then
    -- Do not prevent the rest of the notification deployment because a
    -- legacy profile row may contain invalid pairing data.
    raise notice 'relationship pair seed skipped: %', sqlerrm;
end $$;

-- Keep the permanent relationship identity synchronized whenever the existing
-- pairing RPC changes profiles.paired_with.
create or replace function public.sync_relationship_pair_on_profile_pairing()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_a uuid;
  v_b uuid;
begin
  if new.paired_with is null then
    return new;
  end if;

  if new.id = new.paired_with then
    return new;
  end if;

  v_a := least(new.id, new.paired_with);
  v_b := greatest(new.id, new.paired_with);

  insert into public.relationship_pairs(
    user_a_id,user_b_id,first_paired_at,last_paired_at,is_active,ended_at,updated_at
  )
  values (v_a,v_b,now(),now(),true,null,now())
  on conflict (user_a_id,user_b_id)
  do update set
    is_active=true,
    ended_at=null,
    last_paired_at=now(),
    updated_at=now();

  return new;
end;
$$;

drop trigger if exists profiles_pairing_relationship_sync on public.profiles;
create trigger profiles_pairing_relationship_sync
after update of paired_with on public.profiles
for each row
when (new.paired_with is distinct from old.paired_with and new.paired_with is not null)
execute function public.sync_relationship_pair_on_profile_pairing();

-- Stable relationship lookup used by the Flutter side.
create or replace function public.get_relationship_pair_id(p_partner_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_a uuid;
  v_b uuid;
  v_id uuid;
begin
  if v_me is null then raise exception 'Authentication required'; end if;
  if p_partner_id is null or p_partner_id = v_me then
    raise exception 'Invalid partner';
  end if;

  v_a := least(v_me,p_partner_id);
  v_b := greatest(v_me,p_partner_id);

  select id into v_id
  from public.relationship_pairs
  where user_a_id=v_a and user_b_id=v_b;

  return v_id;
end;
$$;

revoke all on function public.get_relationship_pair_id(uuid) from public;
grant execute on function public.get_relationship_pair_id(uuid) to authenticated;

-- End the current pairing and notify the partner in the partner's own app
-- language. The notification is inserted BEFORE paired_with is cleared so
-- create_notification's existing security rule still permits it.
create or replace function public.unpair_current_user()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_partner uuid;
  v_relationship_id uuid;
  v_notification_id uuid;
  v_partner_language text := 'en';
  v_username text := 'Bestie';
  v_title text;
  v_body text;
  v_event_key text;
  v_a uuid;
  v_b uuid;
begin
  if v_me is null then
    raise exception 'Authentication required';
  end if;

  select paired_with into v_partner
  from public.profiles
  where id=v_me
  for update;

  if v_partner is null then
    return jsonb_build_object(
      'partner_id', null,
      'relationship_id', null,
      'notification_id', null
    );
  end if;

  perform 1 from public.profiles where id=v_partner for update;

  select username into v_username
  from public.profiles
  where id=v_me;

  select language_code into v_partner_language
  from public.profiles
  where id=v_partner;

  v_partner_language := case
    when v_partner_language in ('tr','en','de','es','fr') then v_partner_language
    else 'en'
  end;

  v_a := least(v_me,v_partner);
  v_b := greatest(v_me,v_partner);

  select id into v_relationship_id
  from public.relationship_pairs
  where user_a_id=v_a and user_b_id=v_b
  for update;

  v_event_key := 'pairing_ended:' || v_me::text || ':' || v_partner::text || ':' || coalesce(v_relationship_id::text,'none');

  case v_partner_language
    when 'tr' then
      v_title := 'Eşleşme sona erdi 💔';
      v_body := coalesce(v_username,'Bestie') || ' eşleşmeyi bitirdi.';
    when 'de' then
      v_title := 'Verbindung beendet 💔';
      v_body := coalesce(v_username,'Bestie') || ' hat die Verbindung beendet.';
    when 'es' then
      v_title := 'El emparejamiento terminó 💔';
      v_body := coalesce(v_username,'Bestie') || ' terminó el emparejamiento.';
    when 'fr' then
      v_title := 'Le jumelage est terminé 💔';
      v_body := coalesce(v_username,'Bestie') || ' a mis fin au jumelage.';
    else
      v_title := 'Pairing ended 💔';
      v_body := coalesce(v_username,'Bestie') || ' ended the pairing.';
  end case;

  if to_regclass('public.notifications') is not null then
    begin
      v_notification_id := public.create_notification(
        v_partner,
        v_title,
        v_body,
        'pairing',
        jsonb_build_object(
          'action','unpaired',
          'event_key',v_event_key,
          'relationship_id',v_relationship_id,
          'partner_id',v_me
        )
      );
    exception when others then
      raise notice 'pairing-end notification could not be created: %', sqlerrm;
    end;
  end if;

  if v_relationship_id is not null then
    update public.relationship_pairs
    set is_active=false,
        ended_at=now(),
        updated_at=now()
    where id=v_relationship_id;
  end if;

  update public.profiles
  set paired_with=null, updated_at=now()
  where id in (v_me,v_partner);

  return jsonb_build_object(
    'partner_id',v_partner,
    'relationship_id',v_relationship_id,
    'notification_id',v_notification_id
  );
end;
$$;

revoke all on function public.unpair_current_user() from public;
grant execute on function public.unpair_current_user() to authenticated;

notify pgrst, 'reload schema';

-- Harden push delivery authorization. Every client-created notification carries
-- its creator in data.sender_id. Scheduled/service-role notifications remain
-- deliverable with the service role key.
create or replace function public.create_notification(
  p_user_id uuid,
  p_title text,
  p_body text,
  p_type text default 'general',
  p_data jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_event_key text;
  v_data jsonb;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if p_user_id <> auth.uid() and not exists (
    select 1 from public.profiles
    where id = auth.uid() and paired_with = p_user_id
  ) then
    raise exception 'not allowed to create notification for this user';
  end if;

  v_event_key := nullif(trim(coalesce(p_data->>'event_key', '')), '');
  v_data := coalesce(p_data, '{}'::jsonb) || jsonb_build_object('sender_id', auth.uid());

  if v_event_key is not null then
    select id into v_id
    from public.notifications
    where user_id = p_user_id
      and data->>'event_key' = v_event_key
    order by created_at desc
    limit 1;
    if v_id is not null then return v_id; end if;
  end if;

  insert into public.notifications(user_id,title,body,type,data)
  values (
    p_user_id,p_title,p_body,
    coalesce(nullif(trim(p_type),''),'general'),
    v_data
  )
  returning id into v_id;

  return v_id;
exception
  when unique_violation then
    if v_event_key is not null then
      select id into v_id
      from public.notifications
      where user_id=p_user_id
        and data->>'event_key'=v_event_key
      order by created_at desc
      limit 1;
      if v_id is not null then return v_id; end if;
    end if;
    raise;
end;
$$;

revoke all on function public.create_notification(uuid,text,text,text,jsonb) from public;
grant execute on function public.create_notification(uuid,text,text,text,jsonb) to authenticated;
