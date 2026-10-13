-- BESTIE mood realtime
-- Allows the partner home header to receive mood changes immediately.

do $$
begin
  alter publication supabase_realtime add table public.mood_entries;
exception
  when duplicate_object then null;
end
$$;
