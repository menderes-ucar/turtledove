-- BESTIE media + notification hardening
-- Run after the existing notification migration.

-- Chat media is rendered directly by the Flutter client using public URLs.
-- Make the messages bucket public while keeping uploads restricted by RLS.
insert into storage.buckets (id, name, public)
values ('messages', 'messages', true)
on conflict (id) do update set public = true;

-- Allow authenticated users to upload into their own user folder.
drop policy if exists messages_storage_insert_own on storage.objects;
create policy messages_storage_insert_own
on storage.objects for insert to authenticated
with check (
  bucket_id = 'messages'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Allow authenticated users to read message media.
drop policy if exists messages_storage_select_authenticated on storage.objects;
create policy messages_storage_select_authenticated
on storage.objects for select to authenticated
using (bucket_id = 'messages');

-- Keep notifications realtime and make the old is_read/read_at variants
-- interoperable on installations created by either migration generation.
alter table public.notifications add column if not exists is_read boolean;
update public.notifications
set is_read = (read_at is not null)
where is_read is null;

create or replace function public.sync_notification_read_state()
returns trigger
language plpgsql
as $$
begin
  if new.read_at is distinct from old.read_at then
    new.is_read := new.read_at is not null;
  elsif new.is_read is distinct from old.is_read then
    new.read_at := case when new.is_read then coalesce(old.read_at, now()) else null end;
  end if;
  return new;
end;
$$;

drop trigger if exists notifications_sync_read_state on public.notifications;
create trigger notifications_sync_read_state
before update on public.notifications
for each row execute function public.sync_notification_read_state();

-- Device token registry used by the Edge Function to deliver FCM pushes.
create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null unique,
  platform text not null default 'android',
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create unique index if not exists device_tokens_token_uidx on public.device_tokens(token);

create index if not exists device_tokens_user_idx
  on public.device_tokens(user_id);

alter table public.device_tokens enable row level security;

drop policy if exists device_tokens_select_own on public.device_tokens;
create policy device_tokens_select_own on public.device_tokens
  for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists device_tokens_insert_own on public.device_tokens;
create policy device_tokens_insert_own on public.device_tokens
  for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists device_tokens_update_own on public.device_tokens;
create policy device_tokens_update_own on public.device_tokens
  for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists device_tokens_delete_own on public.device_tokens;
create policy device_tokens_delete_own on public.device_tokens
  for delete to authenticated
  using (auth.uid() = user_id);
