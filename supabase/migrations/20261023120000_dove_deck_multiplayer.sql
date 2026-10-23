-- Dove Deck: partner-only multiplayer state, with all state mutations behind RPCs.
create table if not exists public.dove_deck_games (
  id uuid primary key default gen_random_uuid(),
  player_one uuid not null references auth.users(id) on delete cascade,
  player_two uuid not null references auth.users(id) on delete cascade,
  status text not null default 'waiting' check (status in ('waiting','playing','finished','abandoned')),
  state jsonb not null default '{}'::jsonb,
  version bigint not null default 0,
  current_turn uuid,
  winner uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint dove_deck_distinct_players check (player_one <> player_two)
);

create index if not exists dove_deck_games_player_one_active
  on public.dove_deck_games (player_one, updated_at desc) where status in ('waiting','playing');
create index if not exists dove_deck_games_player_two_active
  on public.dove_deck_games (player_two, updated_at desc) where status in ('waiting','playing');

alter table public.dove_deck_games enable row level security;
drop policy if exists dove_deck_players_read on public.dove_deck_games;
create policy dove_deck_players_read on public.dove_deck_games
  for select to authenticated
  using (auth.uid() = player_one or auth.uid() = player_two);

revoke insert, update, delete on public.dove_deck_games from anon, authenticated;
grant select on public.dove_deck_games to authenticated;

create or replace function public.dove_deck_create_game(p_partner_id uuid)
returns public.dove_deck_games
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user uuid := auth.uid();
  v_game public.dove_deck_games;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_partner_id is null or p_partner_id = v_user then raise exception 'Invalid partner'; end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = v_user and p.paired_with = p_partner_id
  ) then raise exception 'Only your paired partner can play'; end if;

  perform pg_advisory_xact_lock(hashtextextended(least(v_user::text, p_partner_id::text) || ':' || greatest(v_user::text, p_partner_id::text), 0));
  select * into v_game from public.dove_deck_games
    where status in ('waiting','playing')
      and ((player_one = v_user and player_two = p_partner_id) or (player_one = p_partner_id and player_two = v_user))
    order by created_at desc limit 1;
  if found then return v_game; end if;

  insert into public.dove_deck_games(player_one, player_two, status, current_turn)
  values (v_user, p_partner_id, 'waiting', v_user)
  returning * into v_game;
  return v_game;
end;
$$;

create or replace function public.dove_deck_start_game(p_game_id uuid, p_initial_state jsonb)
returns public.dove_deck_games
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user uuid := auth.uid();
  v_game public.dove_deck_games;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if jsonb_typeof(p_initial_state) <> 'object' then raise exception 'Invalid game state'; end if;
  select * into v_game from public.dove_deck_games where id = p_game_id for update;
  if not found or v_user not in (v_game.player_one, v_game.player_two) then raise exception 'Game not found'; end if;
  if v_game.status <> 'waiting' then raise exception 'Game is not waiting'; end if;
  if v_user <> v_game.player_one and v_user <> v_game.player_two then raise exception 'Not a player'; end if;
  update public.dove_deck_games
    set status = 'playing', state = p_initial_state, current_turn = player_one,
        version = version + 1, updated_at = now()
    where id = p_game_id returning * into v_game;
  return v_game;
end;
$$;

create or replace function public.dove_deck_submit_state(
  p_game_id uuid,
  p_expected_version bigint,
  p_state jsonb,
  p_next_turn uuid,
  p_winner uuid default null
)
returns public.dove_deck_games
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user uuid := auth.uid();
  v_game public.dove_deck_games;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if jsonb_typeof(p_state) <> 'object' then raise exception 'Invalid game state'; end if;
  select * into v_game from public.dove_deck_games where id = p_game_id for update;
  if not found or v_user not in (v_game.player_one, v_game.player_two) then raise exception 'Game not found'; end if;
  if v_game.status <> 'playing' then raise exception 'Game is not active'; end if;
  if v_game.version <> p_expected_version then raise exception 'STALE_GAME_STATE'; end if;
  if v_game.current_turn <> v_user then raise exception 'NOT_YOUR_TURN'; end if;
  if p_next_turn not in (v_game.player_one, v_game.player_two) then raise exception 'Invalid next player'; end if;
  if p_winner is not null and p_winner not in (v_game.player_one, v_game.player_two) then raise exception 'Invalid winner'; end if;
  update public.dove_deck_games
    set state = p_state, current_turn = p_next_turn, winner = p_winner,
        status = case when p_winner is null then 'playing' else 'finished' end,
        version = version + 1, updated_at = now()
    where id = p_game_id returning * into v_game;
  return v_game;
end;
$$;

revoke all on function public.dove_deck_create_game(uuid) from public;
revoke all on function public.dove_deck_start_game(uuid, jsonb) from public;
revoke all on function public.dove_deck_submit_state(uuid, bigint, jsonb, uuid, uuid) from public;
grant execute on function public.dove_deck_create_game(uuid) to authenticated;
grant execute on function public.dove_deck_start_game(uuid, jsonb) to authenticated;
grant execute on function public.dove_deck_submit_state(uuid, bigint, jsonb, uuid, uuid) to authenticated;
