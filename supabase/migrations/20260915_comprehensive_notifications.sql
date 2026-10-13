-- BESTIE comprehensive notification backend
-- Run once in Supabase SQL Editor after the notifications table/RPC exists.

create extension if not exists pgcrypto;

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  body text not null,
  type text not null default 'general',
  data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

-- Older installations of the first notification patch used is_read.
alter table public.notifications add column if not exists read_at timestamptz;

-- Preserve old read state when that column exists.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'notifications'
      and column_name = 'is_read'
  ) then
    execute 'update public.notifications set read_at = coalesce(read_at, created_at) where is_read = true and read_at is null';
  end if;
end $$;

create index if not exists notifications_user_created_idx
  on public.notifications(user_id, created_at desc);

create index if not exists notifications_user_unread_idx
  on public.notifications(user_id, read_at)
  where read_at is null;

-- event_key lives inside data. It makes game/realtime events idempotent even
-- when both partner devices react to the same realtime change.
create unique index if not exists notifications_user_event_key_uidx
  on public.notifications(user_id, ((data->>'event_key')))
  where data ? 'event_key' and nullif(data->>'event_key', '') is not null;

alter table public.notifications enable row level security;

drop policy if exists notifications_select_own on public.notifications;
create policy notifications_select_own on public.notifications
  for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications
  for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists notifications_delete_own on public.notifications;
create policy notifications_delete_own on public.notifications
  for delete to authenticated
  using (auth.uid() = user_id);

-- SECURITY DEFINER is intentional: the sender must be able to create a row
-- for their paired partner without gaining direct insert access to the table.
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
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  -- A client may only create a notification for itself or its current partner.
  if p_user_id <> auth.uid() and not exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and paired_with = p_user_id
  ) then
    raise exception 'not allowed to create notification for this user';
  end if;

  v_event_key := nullif(trim(coalesce(p_data->>'event_key', '')), '');

  if v_event_key is not null then
    select id into v_id
    from public.notifications
    where user_id = p_user_id
      and data->>'event_key' = v_event_key
    order by created_at desc
    limit 1;

    if v_id is not null then
      return v_id;
    end if;
  end if;

  insert into public.notifications(user_id, title, body, type, data)
  values (
    p_user_id,
    p_title,
    p_body,
    coalesce(nullif(trim(p_type), ''), 'general'),
    coalesce(p_data, '{}'::jsonb)
  )
  returning id into v_id;

  return v_id;
exception
  when unique_violation then
    if v_event_key is not null then
      select id into v_id
      from public.notifications
      where user_id = p_user_id
        and data->>'event_key' = v_event_key
      order by created_at desc
      limit 1;
      if v_id is not null then return v_id; end if;
    end if;
    raise;
end;
$$;

revoke all on function public.create_notification(uuid,text,text,text,jsonb) from public;
grant execute on function public.create_notification(uuid,text,text,text,jsonb) to authenticated;

alter table public.notifications replica identity full;
do $$
begin
  alter publication supabase_realtime add table public.notifications;
exception when duplicate_object then null;
end $$;
