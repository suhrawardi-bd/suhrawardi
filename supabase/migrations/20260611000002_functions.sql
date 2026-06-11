-- CALLED IT! — functions & triggers

-- Generic updated_at maintenance.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger teams_set_updated_at
  before update on public.teams
  for each row execute function public.set_updated_at();
create trigger fixtures_set_updated_at
  before update on public.fixtures
  for each row execute function public.set_updated_at();
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();
create trigger predictions_set_updated_at
  before update on public.predictions
  for each row execute function public.set_updated_at();

-- Profile auto-creation on signup. Anonymous sign-ins also insert into
-- auth.users, so guests get a profile immediately.
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, avatar_seed)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'display_name',
      'Fan-' || upper(substr(replace(new.id::text, '-', ''), 1, 6))
    ),
    encode(extensions.gen_random_bytes(8), 'hex')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- DB-level lock at kickoff: picks can only be written while the fixture is
-- open. Fires when picks change (insert, or update touching a pick), so the
-- service-role scoring job can still set points_awarded/locked_at afterwards.
-- Binds everyone, service role included.
create or replace function private.enforce_prediction_open()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  picks_changed boolean;
begin
  if tg_op = 'INSERT' then
    picks_changed := true;
    if auth.uid() is not null then
      new.user_id := auth.uid();
    end if;
  else
    picks_changed := new.home_pick is distinct from old.home_pick
                  or new.away_pick is distinct from old.away_pick;
  end if;

  if picks_changed and not exists (
    select 1
    from public.fixtures f
    where f.id = new.fixture_id
      and f.kickoff_utc > now()
      and f.status in ('scheduled', 'timed')
      and f.home_id is not null
      and f.away_id is not null
  ) then
    raise exception 'fixture locked';
  end if;

  return new;
end;
$$;

create trigger predictions_enforce_open
  before insert or update on public.predictions
  for each row execute function private.enforce_prediction_open();

-- SECURITY DEFINER membership check: reads league_members with table-owner
-- rights, breaking the leagues <-> league_members RLS recursion.
create or replace function private.is_league_member(_league_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.league_members
    where league_id = _league_id
      and user_id = auth.uid()
  );
$$;

-- League owner is automatically a member.
create or replace function private.handle_new_league()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.league_members (league_id, user_id)
  values (new.id, new.owner_id)
  on conflict do nothing;
  return new;
end;
$$;

create trigger on_league_created
  after insert on public.leagues
  for each row execute function private.handle_new_league();

-- The only join path. Members can't enumerate leagues: a wrong code returns
-- an empty set, indistinguishable from "no access". Anonymous users carry the
-- `authenticated` role, so guests can join leagues and pods (free tier never
-- gates leagues/pods).
create or replace function public.join_league_by_code(p_code text)
returns table (league_id uuid, league_name text)
language plpgsql
security definer
set search_path = public
as $$
declare
  l public.leagues%rowtype;
begin
  if auth.uid() is null then
    return;
  end if;

  select * into l
  from public.leagues
  where invite_code = upper(trim(p_code));

  if not found then
    return;
  end if;

  insert into public.league_members (league_id, user_id)
  values (l.id, auth.uid())
  on conflict do nothing;

  return query select l.id, l.name;
end;
$$;

revoke execute on function public.join_league_by_code(text) from public, anon;
grant execute on function public.join_league_by_code(text) to authenticated;

-- Referral claim: once per joined user, no self-referral. Award size comes
-- from competition rules (configuration, not code); points are credited here
-- so profiles.points never has to be client-writable.
create or replace function public.claim_referral(p_referrer uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_points int;
begin
  if auth.uid() is null
     or p_referrer = auth.uid()
     or not exists (select 1 from public.profiles where id = p_referrer)
     or exists (select 1 from public.referrals where joined_id = auth.uid())
  then
    return false;
  end if;

  select coalesce((rules #>> '{referral,points}')::int, 0)
    into v_points
  from public.competitions
  order by created_at desc
  limit 1;
  v_points := coalesce(v_points, 0);

  insert into public.referrals (referrer_id, joined_id, points_given)
  values (p_referrer, auth.uid(), v_points);

  if v_points > 0 then
    update public.profiles
    set points = points + v_points
    where id = p_referrer;
  end if;

  return true;
exception
  when unique_violation then
    return false;
end;
$$;

revoke execute on function public.claim_referral(uuid) from public, anon;
grant execute on function public.claim_referral(uuid) to authenticated;
