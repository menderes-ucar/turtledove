-- BESTIE Infinity interaction
-- Replace legacy interaction type checks so infinity is accepted.

do $$
declare
  r record;
begin
  for r in select conname from pg_constraint where conrelid = 'public.interactions'::regclass and contype = 'c' and (pg_get_constraintdef(oid) ilike '%hug%' or pg_get_constraintdef(oid) ilike '%miss_you%') loop
    execute format('alter table public.interactions drop constraint if exists %I', r.conname);
  end loop;
exception when undefined_table then null;
end $$;
