-- Dove Deck: persist each player's ready state and enforce both-ready server-side.
alter table public.dove_deck_games
  add column if not exists player_one_ready boolean not null default false,
  add column if not exists player_two_ready boolean not null default false;

create or replace function public.dove_deck_set_ready(p_game_id uuid, p_ready boolean)
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
  select * into v_game from public.dove_deck_games where id = p_game_id for update;
  if not found or v_user not in (v_game.player_one, v_game.player_two) then raise exception 'Game not found'; end if;
  if v_game.status <> 'waiting' then raise exception 'Game is not waiting'; end if;

  update public.dove_deck_games
  set player_one_ready = case when v_user = player_one then p_ready else player_one_ready end,
      player_two_ready = case when v_user = player_two then p_ready else player_two_ready end,
      updated_at = now()
  where id = p_game_id returning * into v_game;
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
  if not v_game.player_one_ready or not v_game.player_two_ready then
    raise exception 'Both players must be ready';
  end if;
  if v_user <> v_game.player_one then raise exception 'Only the game creator can start'; end if;
  update public.dove_deck_games
    set status = 'playing', state = p_initial_state, current_turn = player_one,
        version = version + 1, updated_at = now()
    where id = p_game_id returning * into v_game;
  return v_game;
end;
$$;

revoke all on function public.dove_deck_set_ready(uuid, boolean) from public;
grant execute on function public.dove_deck_set_ready(uuid, boolean) to authenticated;
revoke all on function public.dove_deck_start_game(uuid, jsonb) from public;
grant execute on function public.dove_deck_start_game(uuid, jsonb) to authenticated;
NOTIFY pgrst, 'reload schema';
