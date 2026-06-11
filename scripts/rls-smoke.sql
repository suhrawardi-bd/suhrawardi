-- RLS smoke tests. Run against a local db that has migrations + dev seed:
--   psql "$DATABASE_URL" -f scripts/rls-smoke.sql
-- Everything runs in one rolled-back transaction; raises on first failure,
-- prints "RLS SMOKE TESTS PASSED" on success.

\set ON_ERROR_STOP on

begin;

-- ---------------------------------------------------------------------------
-- Test users (insert as superuser; profile trigger fires for each).
-- ---------------------------------------------------------------------------
insert into auth.users (id, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a1', '{"display_name": "Alice"}'),
  ('00000000-0000-0000-0000-0000000000b2', '{"display_name": "Bob"}');

create or replace function pg_temp.impersonate(uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create or replace function pg_temp.impersonate_anon() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('role', 'anon', true);
end;
$$;

do $$
declare
  alice constant uuid := '00000000-0000-0000-0000-0000000000a1';
  bob   constant uuid := '00000000-0000-0000-0000-0000000000b2';
  fx_open   uuid;
  fx_done   uuid;
  v_league  uuid;
  v_code    text;
  n int;
  ok boolean;
begin
  select id into strict fx_open from public.fixtures where external_id = -101;
  select id into strict fx_done from public.fixtures where external_id = -102;

  -- 1. Signup trigger created profiles with display names from metadata.
  perform 1 from public.profiles where id = alice and display_name = 'Alice';
  if not found then raise exception 'T1: profile trigger failed'; end if;

  -- 2. anon reads catalog tables but cannot write fixtures.
  perform pg_temp.impersonate_anon();
  select count(*) into n from public.fixtures;
  if n < 2 then raise exception 'T2: anon cannot read fixtures'; end if;
  begin
    update public.fixtures set home_score = 9 where id = fx_done;
    raise exception 'T2: anon updated fixtures!';
  exception when insufficient_privilege then null;
  end;
  reset role;

  -- 3. Alice updates her own display_name, but not points, not Bob's row.
  perform pg_temp.impersonate(alice);
  update public.profiles set display_name = 'Alice!' where id = alice;
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'T3: own display_name update failed'; end if;
  begin
    update public.profiles set points = 999 where id = alice;
    raise exception 'T3: client updated points!';
  exception when insufficient_privilege then null;
  end;
  update public.profiles set display_name = 'gotcha' where id = bob;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'T3: updated another user''s profile!'; end if;
  reset role;

  -- 4. Predictions: insert OK on open fixture, rejected on finished fixture,
  --    points_awarded not client-writable.
  perform pg_temp.impersonate(alice);
  insert into public.predictions (user_id, fixture_id, home_pick, away_pick)
  values (alice, fx_open, 2, 1);
  begin
    insert into public.predictions (user_id, fixture_id, home_pick, away_pick)
    values (alice, fx_done, 1, 0);
    raise exception 'T4: predicted a finished fixture!';
  exception when others then
    if sqlerrm not like '%fixture locked%' and sqlstate <> '42501' then raise; end if;
  end;
  begin
    insert into public.predictions (user_id, fixture_id, home_pick, away_pick, points_awarded)
    values (alice, fx_done, 1, 0, 50);
    raise exception 'T4: client wrote points_awarded!';
  exception when insufficient_privilege then null;
  end;
  reset role;

  -- 5. Bob cannot see Alice's pick pre-kickoff; after kickoff he can; and
  --    Alice can no longer change it (DB-level lock binds superuser too).
  perform pg_temp.impersonate(bob);
  select count(*) into n from public.predictions where fixture_id = fx_open;
  if n <> 0 then raise exception 'T5: pick visible before kickoff!'; end if;
  reset role;
  update public.fixtures
  set kickoff_utc = now() - interval '1 hour', status = 'in_play'
  where id = fx_open;
  perform pg_temp.impersonate(bob);
  select count(*) into n from public.predictions where fixture_id = fx_open;
  if n <> 1 then raise exception 'T5: pick not visible after kickoff'; end if;
  reset role;
  perform pg_temp.impersonate(alice);
  begin
    update public.predictions set home_pick = 5
    where user_id = alice and fixture_id = fx_open;
    get diagnostics n = row_count;
    if n > 0 then raise exception 'T5: changed pick after kickoff!'; end if;
  exception when others then
    if sqlerrm not like '%fixture locked%' then raise; end if;
  end;
  reset role;

  -- 6. Leagues: invisible to non-members; join only via invite code RPC.
  perform pg_temp.impersonate(alice);
  insert into public.leagues (name, owner_id) values ('Alice''s Crew', alice);
  reset role;
  select id, invite_code into strict v_league, v_code
  from public.leagues where owner_id = alice;

  perform pg_temp.impersonate(bob);
  select count(*) into n from public.leagues;
  if n <> 0 then raise exception 'T6: non-member sees league!'; end if;
  select count(*) into n from public.join_league_by_code('XXXXXXXXXX');
  if n <> 0 then raise exception 'T6: bogus invite code joined something!'; end if;
  select count(*) into n from public.join_league_by_code(v_code);
  if n <> 1 then raise exception 'T6: valid invite code failed'; end if;
  select count(*) into n from public.leagues where id = v_league;
  if n <> 1 then raise exception 'T6: member cannot see league'; end if;
  select count(*) into n from public.league_members where league_id = v_league;
  if n <> 2 then raise exception 'T6: expected owner+joiner memberships'; end if;
  reset role;

  -- 7. Referrals: direct insert denied; claim works once, never for self.
  perform pg_temp.impersonate(bob);
  begin
    insert into public.referrals (referrer_id, joined_id) values (alice, bob);
    raise exception 'T7: direct referral insert allowed!';
  exception when insufficient_privilege then null;
  end;
  select public.claim_referral(bob) into ok;
  if ok then raise exception 'T7: self-referral allowed!'; end if;
  select public.claim_referral(alice) into ok;
  if not ok then raise exception 'T7: valid referral claim failed'; end if;
  select public.claim_referral(alice) into ok;
  if ok then raise exception 'T7: referral claimed twice!'; end if;
  reset role;

  -- 8. sync_runs is service-role only.
  insert into public.sync_runs (kind) values ('test');
  perform pg_temp.impersonate(alice);
  select count(*) into n from public.sync_runs;
  if n <> 0 then raise exception 'T8: client read sync_runs!'; end if;
  begin
    insert into public.sync_runs (kind) values ('hax');
    raise exception 'T8: client wrote sync_runs!';
  exception when insufficient_privilege then null;
  end;
  reset role;

  raise notice 'RLS SMOKE TESTS PASSED';
end;
$$;

rollback;
