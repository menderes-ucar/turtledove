-- BESTIE Hall of Fame / curated partner gallery
-- One user can curate up to 10 compressed photos total.

create table if not exists public.hall_of_fame_photos (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  partner_id uuid references auth.users(id) on delete set null,
  category text not null check (category in ('aura','meme','mood')),
  storage_path text not null unique,
  public_url text not null,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists hall_of_fame_owner_idx on public.hall_of_fame_photos(owner_id, created_at desc);
create index if not exists hall_of_fame_partner_idx on public.hall_of_fame_photos(partner_id, created_at desc);

alter table public.hall_of_fame_photos enable row level security;

drop policy if exists hall_of_fame_select_paired on public.hall_of_fame_photos;
create policy hall_of_fame_select_paired
on public.hall_of_fame_photos for select to authenticated
using (auth.uid() = owner_id or auth.uid() = partner_id);

drop policy if exists hall_of_fame_insert_own on public.hall_of_fame_photos;
create policy hall_of_fame_insert_own
on public.hall_of_fame_photos for insert to authenticated
with check (auth.uid() = owner_id);

drop policy if exists hall_of_fame_update_own on public.hall_of_fame_photos;
create policy hall_of_fame_update_own
on public.hall_of_fame_photos for update to authenticated
using (auth.uid() = owner_id or auth.uid() = partner_id)
with check (auth.uid() = owner_id or auth.uid() = partner_id);

drop policy if exists hall_of_fame_delete_own on public.hall_of_fame_photos;
create policy hall_of_fame_delete_own
on public.hall_of_fame_photos for delete to authenticated
using (auth.uid() = owner_id);

-- Private storage bucket. Files are already compressed client-side to WebP before upload.
insert into storage.buckets (id, name, public)
values ('hall-of-fame', 'hall-of-fame', false)
on conflict (id) do update set public = false;

drop policy if exists hall_of_fame_storage_insert_own on storage.objects;
create policy hall_of_fame_storage_insert_own
on storage.objects for insert to authenticated
with check (
  bucket_id = 'hall-of-fame'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists hall_of_fame_storage_select_authenticated on storage.objects;
create policy hall_of_fame_storage_select_authenticated
on storage.objects for select to authenticated
using (
  bucket_id = 'hall-of-fame'
  and exists (
    select 1
    from public.hall_of_fame_photos p
    where p.storage_path = name
      and (p.owner_id = auth.uid() or p.partner_id = auth.uid())
  )
);

drop policy if exists hall_of_fame_storage_delete_own on storage.objects;
create policy hall_of_fame_storage_delete_own
on storage.objects for delete to authenticated
using (
  bucket_id = 'hall-of-fame'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Keep the 10-photo limit enforced by the database as well as the UI.
create or replace function public.enforce_hall_of_fame_limit()
returns trigger
language plpgsql
as $$
declare
  photo_count integer;
begin
  -- Serialize concurrent inserts for the same owner.
  perform pg_advisory_xact_lock(hashtextextended(new.owner_id::text, 4815162342));
  select count(*) into photo_count
  from public.hall_of_fame_photos
  where owner_id = new.owner_id;

  if photo_count >= 10 then
    raise exception 'HALL_OF_FAME_LIMIT';
  end if;
  return new;
end;
$$;

drop trigger if exists hall_of_fame_limit_trigger on public.hall_of_fame_photos;
create trigger hall_of_fame_limit_trigger
before insert on public.hall_of_fame_photos
for each row execute function public.enforce_hall_of_fame_limit();

create or replace function public.touch_hall_of_fame_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists hall_of_fame_updated_at_trigger on public.hall_of_fame_photos;
create trigger hall_of_fame_updated_at_trigger
before update on public.hall_of_fame_photos
for each row execute function public.touch_hall_of_fame_updated_at();
