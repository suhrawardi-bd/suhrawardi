-- CALLED IT! — production seed: sport + competition configuration.
-- Idempotent; safe to re-run. Teams and fixtures are populated by the sync.
-- Display name is deliberately neutral — no FIFA/World Cup marks. The
-- internal code 'WC' is only the football-data.org API key, never shown.

insert into public.sports (slug, name)
values ('football', 'Football')
on conflict (slug) do nothing;

insert into public.competitions (sport_id, name, code, season, external_id, rules)
select
  s.id,
  'International Cup 2026',
  'WC',
  2026,
  '2000',
  jsonb_build_object(
    'scoring', jsonb_build_object(
      'exact', 6,
      'winner_gd', 4,
      'winner_or_draw', 3
    ),
    'lock', 'kickoff',
    'score_basis', 'full_time',
    'flags_only', true
  )
from public.sports s
where s.slug = 'football'
on conflict (code, season) do nothing;
