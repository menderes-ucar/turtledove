-- BESTIE: Today, Us + Relationship Streak
create extension if not exists pgcrypto;

create table if not exists public.relationship_daily_activity (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  partner_id uuid not null references auth.users(id) on delete cascade,
  activity_day date not null,
  message_count integer not null default 0,
  photo_count integer not null default 0,
  video_count integer not null default 0,
  game_count integer not null default 0,
  interaction_count integer not null default 0,
  completed_task_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint relationship_daily_activity_pair_check check (user_id <> partner_id),
  constraint relationship_daily_activity_unique unique (user_id, partner_id, activity_day)
);

create index if not exists relationship_daily_activity_pair_day_idx
  on public.relationship_daily_activity(user_id, partner_id, activity_day desc);

alter table public.relationship_daily_activity enable row level security;
drop policy if exists relationship_daily_activity_select_pair on public.relationship_daily_activity;
create policy relationship_daily_activity_select_pair on public.relationship_daily_activity
for select to authenticated using (auth.uid() = user_id or auth.uid() = partner_id);

drop policy if exists relationship_daily_activity_insert_pair on public.relationship_daily_activity;
create policy relationship_daily_activity_insert_pair on public.relationship_daily_activity
for insert to authenticated with check (auth.uid() = user_id or auth.uid() = partner_id);

drop policy if exists relationship_daily_activity_update_pair on public.relationship_daily_activity;
create policy relationship_daily_activity_update_pair on public.relationship_daily_activity
for update to authenticated using (auth.uid() = user_id or auth.uid() = partner_id)
with check (auth.uid() = user_id or auth.uid() = partner_id);

create or replace function public.record_relationship_activity(
  p_user_id uuid,
  p_partner_id uuid,
  p_activity_type text,
  p_activity_day date default current_date,
  p_amount integer default 1
) returns void
language plpgsql security definer set search_path = public
as $$
declare v_type text := lower(trim(p_activity_type));
begin
  if p_user_id is null or p_partner_id is null or p_user_id = p_partner_id then return; end if;
  if not exists (select 1 from profiles where id=p_user_id and paired_with=p_partner_id) then return; end if;
  insert into relationship_daily_activity(user_id, partner_id, activity_day)
  values(p_user_id,p_partner_id,p_activity_day)
  on conflict (user_id,partner_id,activity_day) do nothing;
  if v_type = 'message' then update relationship_daily_activity set message_count=message_count+greatest(p_amount,1),updated_at=now() where user_id=p_user_id and partner_id=p_partner_id and activity_day=p_activity_day;
  elsif v_type = 'photo' then update relationship_daily_activity set photo_count=photo_count+greatest(p_amount,1),updated_at=now() where user_id=p_user_id and partner_id=p_partner_id and activity_day=p_activity_day;
  elsif v_type = 'video' then update relationship_daily_activity set video_count=video_count+greatest(p_amount,1),updated_at=now() where user_id=p_user_id and partner_id=p_partner_id and activity_day=p_activity_day;
  elsif v_type = 'game' then update relationship_daily_activity set game_count=game_count+greatest(p_amount,1),updated_at=now() where user_id=p_user_id and partner_id=p_partner_id and activity_day=p_activity_day;
  elsif v_type = 'interaction' then update relationship_daily_activity set interaction_count=interaction_count+greatest(p_amount,1),updated_at=now() where user_id=p_user_id and partner_id=p_partner_id and activity_day=p_activity_day;
  elsif v_type = 'task' then update relationship_daily_activity set completed_task_count=completed_task_count+greatest(p_amount,1),updated_at=now() where user_id=p_user_id and partner_id=p_partner_id and activity_day=p_activity_day;
  end if;
end;
$$;

-- Mirror activity in both directions so either partner can read the same history.
create or replace function public.relationship_activity_from_message()
returns trigger language plpgsql security definer set search_path=public as $$
declare t text; begin
  if new.sender_id is null or new.receiver_id is null then return new; end if;
  t := case when coalesce(new.media_url,'') <> '' then case when lower(new.media_url) ~ '\\.(mp4|mov|m4v|webm|avi)([?#].*)?$' then 'video' else 'photo' end else 'message' end;
  perform record_relationship_activity(new.sender_id,new.receiver_id,t,(new.created_at at time zone 'UTC')::date);
  perform record_relationship_activity(new.receiver_id,new.sender_id,t,(new.created_at at time zone 'UTC')::date);
  return new;
end $$;
drop trigger if exists relationship_activity_messages on public.messages;
create trigger relationship_activity_messages after insert on public.messages for each row execute function public.relationship_activity_from_message();

create or replace function public.relationship_activity_from_interaction()
returns trigger language plpgsql security definer set search_path=public as $$ begin
  perform record_relationship_activity(new.sender_id,new.receiver_id,'interaction',(new.created_at at time zone 'UTC')::date);
  perform record_relationship_activity(new.receiver_id,new.sender_id,'interaction',(new.created_at at time zone 'UTC')::date);
  return new;
end $$;
drop trigger if exists relationship_activity_interactions on public.interactions;
create trigger relationship_activity_interactions after insert on public.interactions for each row execute function public.relationship_activity_from_interaction();

create or replace function public.get_relationship_daily_stats(p_user_id uuid,p_partner_id uuid,p_day date)
returns table(messages integer,photos integer,videos integer,games integer,interactions integer,completed_todos integer)
language sql stable security definer set search_path=public as $$
select coalesce(message_count,0),coalesce(photo_count,0),coalesce(video_count,0),coalesce(game_count,0),coalesce(interaction_count,0),coalesce(completed_task_count,0)
from relationship_daily_activity where user_id=p_user_id and partner_id=p_partner_id and activity_day=p_day
union all select 0,0,0,0,0,0 where not exists(select 1 from relationship_daily_activity where user_id=p_user_id and partner_id=p_partner_id and activity_day=p_day)
limit 1;
$$;


create or replace function public.get_relationship_recent_stats(p_user_id uuid,p_partner_id uuid,p_days integer default 7)
returns table(day date,messages integer,photos integer,videos integer,games integer,interactions integer,completed_todos integer)
language sql stable security definer set search_path=public as $$
select d::date,coalesce(a.message_count,0),coalesce(a.photo_count,0),coalesce(a.video_count,0),coalesce(a.game_count,0),coalesce(a.interaction_count,0),coalesce(a.completed_task_count,0)
from generate_series(current_date - greatest(p_days-1,0),current_date,interval '1 day') d
left join relationship_daily_activity a on a.user_id=p_user_id and a.partner_id=p_partner_id and a.activity_day=d::date
order by d;
$$;

create or replace function public.get_relationship_streak(p_user_id uuid,p_partner_id uuid)
returns table(current_streak integer,longest_streak integer,active_today boolean,last_active_day date)
language plpgsql stable security definer set search_path=public as $$
declare d date; cur integer:=0; best integer:=0; run integer:=0; last_day date;
begin
  for d in select distinct activity_day from relationship_daily_activity where user_id=p_user_id and partner_id=p_partner_id and (message_count+photo_count+video_count+game_count+interaction_count+completed_task_count)>0 order by activity_day desc loop
    if last_day is null then last_day:=d; run:=1;
    elsif last_day-d=1 then run:=run+1; last_day:=d;
    else exit; end if;
  end loop;
  cur:=case when last_day=current_date then run else 0 end;
  select coalesce(max(streak),0) into best from (
    select count(*)::int streak from (select activity_day, activity_day-(row_number() over(order by activity_day))::int grp from relationship_daily_activity where user_id=p_user_id and partner_id=p_partner_id and (message_count+photo_count+video_count+game_count+interaction_count+completed_task_count)>0) x group by grp
  ) q;
  return query select cur,best,last_day=current_date,last_day;
end $$;

create or replace function public.ensure_relationship_daily_notification(p_user_id uuid,p_partner_id uuid,p_title text,p_body text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_key text := 'today_us:'||current_date::text||':'||least(p_user_id::text,p_partner_id::text)||':'||greatest(p_user_id::text,p_partner_id::text);
begin
  select id into v_id from notifications where user_id=p_user_id and data->>'event_key'=v_key limit 1;
  if v_id is not null then return v_id; end if;
  return create_notification(p_user_id,p_title,p_body,'today_us',jsonb_build_object('event_key',v_key,'action','open_us','type','today_us'));
end $$;

-- Permissions
revoke all on function public.record_relationship_activity(uuid,uuid,text,date,integer) from public;
grant execute on function public.record_relationship_activity(uuid,uuid,text,date,integer) to authenticated;
grant execute on function public.get_relationship_daily_stats(uuid,uuid,date) to authenticated;
grant execute on function public.get_relationship_recent_stats(uuid,uuid,integer) to authenticated;
grant execute on function public.get_relationship_streak(uuid,uuid) to authenticated;
grant execute on function public.ensure_relationship_daily_notification(uuid,uuid,text,text) to authenticated;

alter table public.relationship_daily_activity replica identity full;
do $$ begin alter publication supabase_realtime add table public.relationship_daily_activity; exception when duplicate_object then null; end $$;

create or replace function public.relationship_activity_from_game_session()
returns trigger language plpgsql security definer set search_path=public as $$
declare partner uuid;
begin
  partner := (select paired_with from profiles where id=new.created_by);
  if partner is not null then
    perform record_relationship_activity(new.created_by,partner,'game',(new.created_at at time zone 'UTC')::date);
    perform record_relationship_activity(partner,new.created_by,'game',(new.created_at at time zone 'UTC')::date);
  end if;
  return new;
end $$;
drop trigger if exists relationship_activity_game_sessions on public.game_sessions;
create trigger relationship_activity_game_sessions after insert on public.game_sessions for each row execute function public.relationship_activity_from_game_session();

-- Server scheduler helper. Only the service role can call this function.
create or replace function public.create_system_relationship_notification(
  p_user_id uuid,p_title text,p_body text,p_type text,p_data jsonb
) returns uuid language sql security definer set search_path=public as $$
  insert into public.notifications(user_id,title,body,type,data)
  values(p_user_id,p_title,p_body,coalesce(nullif(trim(p_type),''),'general'),coalesce(p_data,'{}'::jsonb))
  on conflict do nothing
  returning id;
$$;
revoke all on function public.create_system_relationship_notification(uuid,text,text,text,jsonb) from public;
grant execute on function public.create_system_relationship_notification(uuid,text,text,text,jsonb) to service_role;

-- Backfill recent history so installing this feature does not start with an empty dashboard.
do $$
declare r record;
begin
  for r in select sender_id a, receiver_id b, (created_at at time zone 'UTC')::date d,
    case when coalesce(media_url,'')='' then 'message' when lower(media_url) ~ '\\.(mp4|mov|m4v|webm|avi)([?#].*)?$' then 'video' else 'photo' end t
    from public.messages where created_at >= now() - interval '90 days'
  loop perform record_relationship_activity(r.a,r.b,r.t,r.d); perform record_relationship_activity(r.b,r.a,r.t,r.d); end loop;
  for r in select sender_id a, receiver_id b, (created_at at time zone 'UTC')::date d from public.interactions where created_at >= now() - interval '90 days'
  loop perform record_relationship_activity(r.a,r.b,'interaction',r.d); perform record_relationship_activity(r.b,r.a,'interaction',r.d); end loop;
  for r in select created_by a, (select paired_with from public.profiles where id=created_by) b, (created_at at time zone 'UTC')::date d from public.game_sessions where created_at >= now() - interval '90 days'
  loop if r.b is not null then perform record_relationship_activity(r.a,r.b,'game',r.d); perform record_relationship_activity(r.b,r.a,'game',r.d); end if; end loop;
end $$;
