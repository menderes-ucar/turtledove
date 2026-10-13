create table if not exists public.theme_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  is_dark boolean not null default false,
  color_index integer not null default 0 check (color_index between 0 and 4),
  updated_at timestamptz not null default now()
);

alter table public.theme_preferences enable row level security;

drop policy if exists "theme select own and partner" on public.theme_preferences;
create policy "theme select own and partner" on public.theme_preferences for select to authenticated using (
  user_id = auth.uid() or exists (
    select 1 from public.profiles p where p.id = auth.uid() and p.paired_with = theme_preferences.user_id
  )
);

drop policy if exists "theme insert own" on public.theme_preferences;
create policy "theme insert own" on public.theme_preferences for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "theme update own" on public.theme_preferences;
create policy "theme update own" on public.theme_preferences for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table public.theme_preferences replica identity full;


do $$
begin
  alter publication supabase_realtime add table public.theme_preferences;
exception when duplicate_object then null;
end $$;
