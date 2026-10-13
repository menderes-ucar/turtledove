-- BESTIE call hardening: WhatsApp-style incoming call wake-up + durable realtime.
-- Run this migration on the deployed Supabase project before testing the new build.

-- ---------------------------------------------------------------------------
-- Durable call tables. Existing installations are preserved; missing columns
-- are added so older deployments converge to the schema expected by Flutter.
-- ---------------------------------------------------------------------------
create table if not exists public.call_sessions (
  id uuid primary key default gen_random_uuid(),
  caller_id uuid not null references auth.users(id) on delete cascade,
  receiver_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'ringing',
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  ended_at timestamptz
);

alter table public.call_sessions add column if not exists caller_id uuid;
alter table public.call_sessions add column if not exists receiver_id uuid;
alter table public.call_sessions add column if not exists status text;
alter table public.call_sessions add column if not exists created_at timestamptz;
alter table public.call_sessions add column if not exists accepted_at timestamptz;
alter table public.call_sessions add column if not exists ended_at timestamptz;
alter table public.call_sessions alter column id set default gen_random_uuid();
alter table public.call_sessions alter column status set default 'ringing';
alter table public.call_sessions alter column created_at set default now();
update public.call_sessions set status = 'ringing' where status is null;
update public.call_sessions set created_at = now() where created_at is null;

create index if not exists call_sessions_receiver_status_idx
  on public.call_sessions(receiver_id, status, created_at desc);
create index if not exists call_sessions_caller_created_idx
  on public.call_sessions(caller_id, created_at desc);

alter table public.call_sessions enable row level security;

drop policy if exists call_sessions_select_participant on public.call_sessions;
create policy call_sessions_select_participant on public.call_sessions
  for select to authenticated
  using (auth.uid() = caller_id or auth.uid() = receiver_id);

drop policy if exists call_sessions_insert_caller on public.call_sessions;
create policy call_sessions_insert_caller on public.call_sessions
  for insert to authenticated
  with check (auth.uid() = caller_id);

drop policy if exists call_sessions_update_participant on public.call_sessions;
create policy call_sessions_update_participant on public.call_sessions
  for update to authenticated
  using (auth.uid() = caller_id or auth.uid() = receiver_id)
  with check (auth.uid() = caller_id or auth.uid() = receiver_id);

alter table public.call_sessions replica identity full;

create table if not exists public.call_signals (
  id uuid primary key default gen_random_uuid(),
  call_id uuid not null references public.call_sessions(id) on delete cascade,
  from_user_id uuid not null references auth.users(id) on delete cascade,
  to_user_id uuid not null references auth.users(id) on delete cascade,
  type text not null,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.call_signals add column if not exists call_id uuid;
alter table public.call_signals add column if not exists from_user_id uuid;
alter table public.call_signals add column if not exists to_user_id uuid;
alter table public.call_signals add column if not exists type text;
alter table public.call_signals add column if not exists data jsonb;
alter table public.call_signals add column if not exists created_at timestamptz;
alter table public.call_signals alter column data set default '{}'::jsonb;
alter table public.call_signals alter column created_at set default now();
update public.call_signals set data = '{}'::jsonb where data is null;
update public.call_signals set created_at = now() where created_at is null;

create index if not exists call_signals_to_call_created_idx
  on public.call_signals(to_user_id, call_id, created_at);
create index if not exists call_signals_call_created_idx
  on public.call_signals(call_id, created_at);

alter table public.call_signals enable row level security;

drop policy if exists call_signals_select_participant on public.call_signals;
create policy call_signals_select_participant on public.call_signals
  for select to authenticated
  using (auth.uid() = from_user_id or auth.uid() = to_user_id);

drop policy if exists call_signals_insert_sender on public.call_signals;
create policy call_signals_insert_sender on public.call_signals
  for insert to authenticated
  with check (auth.uid() = from_user_id);

alter table public.call_signals replica identity full;

-- ---------------------------------------------------------------------------
-- Realtime is essential while the partner already has BESTIE open. Without
-- these publication entries, HomeScreen's incomingCalls() stream has nothing
-- to receive even though the call_sessions row exists.
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'call_sessions'
  ) then
    alter publication supabase_realtime add table public.call_sessions;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'call_signals'
  ) then
    alter publication supabase_realtime add table public.call_signals;
  end if;
end $$;

-- Device token registry required by send-push-notification.
create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null unique,
  platform text not null default 'android',
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create unique index if not exists device_tokens_token_uidx on public.device_tokens(token);
create index if not exists device_tokens_user_idx on public.device_tokens(user_id);
alter table public.device_tokens enable row level security;

drop policy if exists device_tokens_select_own on public.device_tokens;
create policy device_tokens_select_own on public.device_tokens
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists device_tokens_insert_own on public.device_tokens;
create policy device_tokens_insert_own on public.device_tokens
  for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists device_tokens_update_own on public.device_tokens;
create policy device_tokens_update_own on public.device_tokens
  for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists device_tokens_delete_own on public.device_tokens;
create policy device_tokens_delete_own on public.device_tokens
  for delete to authenticated using (auth.uid() = user_id);

create or replace function public.register_device_token(
  p_token text,
  p_platform text default 'android'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.device_tokens where token = p_token;
  insert into public.device_tokens(user_id, token, platform, updated_at)
  values (auth.uid(), p_token, coalesce(nullif(p_platform, ''), 'android'), now());
end;
$$;

revoke all on function public.register_device_token(text, text) from public;
grant execute on function public.register_device_token(text, text) to authenticated;

-- Ask PostgREST to refresh its schema cache after the migration.
notify pgrst, 'reload schema';
