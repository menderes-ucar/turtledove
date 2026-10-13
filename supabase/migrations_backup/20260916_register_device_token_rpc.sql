-- Ensure the device-token RPC exists in projects where the previous
-- hardening migration was not applied or PostgREST has not seen the function.
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
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  delete from public.device_tokens where token = p_token;
  insert into public.device_tokens(user_id, token, platform, updated_at)
  values (auth.uid(), p_token, coalesce(nullif(p_platform, ''), 'android'), now());
end;
$$;

revoke all on function public.register_device_token(text, text) from public;
grant execute on function public.register_device_token(text, text) to authenticated;
notify pgrst, 'reload schema';
