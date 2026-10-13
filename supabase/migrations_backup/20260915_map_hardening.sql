-- BESTIE shared map schema and realtime hardening

create table if not exists public.map_selections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  partner_id uuid not null references auth.users(id) on delete cascade,
  selection_key text not null unique,
  country_code text not null,
  country_name text not null,
  city_name text,
  state_name text,
  city_id integer,
  latitude double precision,
  longitude double precision,
  created_at timestamptz not null default now(),
  constraint map_selection_not_self check (user_id <> partner_id)
);

alter table public.map_selections add column if not exists partner_id uuid references auth.users(id) on delete cascade;
alter table public.map_selections add column if not exists selection_key text;
alter table public.map_selections add column if not exists country_code text;
alter table public.map_selections add column if not exists country_name text;
alter table public.map_selections add column if not exists city_name text;
alter table public.map_selections add column if not exists state_name text;
alter table public.map_selections add column if not exists city_id integer;
alter table public.map_selections add column if not exists latitude double precision;
alter table public.map_selections add column if not exists longitude double precision;
alter table public.map_selections add column if not exists created_at timestamptz not null default now();

alter table public.map_selections enable row level security;

drop policy if exists map_select_pair on public.map_selections;
create policy map_select_pair on public.map_selections
for select to authenticated using (
  user_id = auth.uid()
  or partner_id = auth.uid()
  or exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and (p.paired_with = map_selections.user_id or p.paired_with = map_selections.partner_id)
  )
);

drop policy if exists map_insert_own on public.map_selections;
create policy map_insert_own on public.map_selections
for insert to authenticated with check (
  user_id = auth.uid()
  and partner_id = (select paired_with from public.profiles where id = auth.uid())
);

drop policy if exists map_delete_own on public.map_selections;
create policy map_delete_own on public.map_selections
for delete to authenticated using (user_id = auth.uid());

alter table public.map_selections replica identity full;

create index if not exists map_selections_pair_idx
  on public.map_selections(user_id, partner_id, created_at desc);

create index if not exists map_selections_country_idx
  on public.map_selections(country_code);

do $$
begin
  alter publication supabase_realtime add table public.map_selections;
exception when duplicate_object then null;
end $$;

create unique index if not exists map_selections_selection_key_uidx on public.map_selections(selection_key);
