-- Dev-only sample data, applied by `supabase db reset` after migrations.
-- Never run in production. Negative external_ids cannot collide with real
-- football-data.org ids.

do $$
declare
  v_comp uuid;
  v_home uuid;
  v_away uuid;
begin
  select id into v_comp
  from public.competitions
  where code = 'WC' and season = 2026;

  insert into public.teams (competition_id, name, short_code, flag_code, ranking, external_id)
  values (v_comp, 'Devland', 'DEV', 'AQ', 1, -1)
  on conflict (competition_id, external_id) do nothing;

  insert into public.teams (competition_id, name, short_code, flag_code, ranking, external_id)
  values (v_comp, 'Testonia', 'TST', 'UN', 2, -2)
  on conflict (competition_id, external_id) do nothing;

  select id into v_home from public.teams where competition_id = v_comp and external_id = -1;
  select id into v_away from public.teams where competition_id = v_comp and external_id = -2;

  -- One open fixture (predictions allowed) ...
  insert into public.fixtures
    (competition_id, home_id, away_id, kickoff_utc, venue_city, status, external_id)
  values
    (v_comp, v_home, v_away, now() + interval '2 days', 'Devtown', 'timed', -101)
  on conflict (external_id) do nothing;

  -- ... and one finished fixture (locked, scored).
  insert into public.fixtures
    (competition_id, home_id, away_id, kickoff_utc, venue_city, status,
     home_score, away_score, external_id)
  values
    (v_comp, v_away, v_home, now() - interval '2 days', 'Testville', 'finished',
     2, 1, -102)
  on conflict (external_id) do nothing;
end;
$$;
