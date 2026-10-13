-- BESTIE notification base schema
-- This file contains PostgreSQL only.
-- iOS/Flutter code belongs in ios/Runner/AppDelegate.swift, not in Supabase migrations.

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

alter table public.notifications
  add column if not exists title text,
  add column if not exists body text,
  add column if not exists type text,
  add column if not exists data jsonb,
  add column if not exists read_at timestamptz,
  add column if not exists created_at timestamptz;

update public.notifications
set
  type = coalesce(type, 'general'),
  data = coalesce(data, '{}'::jsonb),
  created_at = coalesce(created_at, now())
where type is null
   or data is null
   or created_at is null;

create index if not exists notifications_user_created_idx
  on public.notifications(user_id, created_at desc);

alter table public.notifications enable row level security;

drop policy if exists notifications_select_own on public.notifications;
create policy notifications_select_own
on public.notifications for select to authenticated
using (auth.uid() = user_id);

drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own
on public.notifications for update to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists notifications_delete_own on public.notifications;
create policy notifications_delete_own
on public.notifications for delete to authenticated
using (auth.uid() = user_id);

alter table public.notifications replica identity full;

do $$
begin
  alter publication supabase_realtime add table public.notifications;
exception
  when duplicate_object then null;
end
$$;
