-- CALLED IT! — initial schema
-- Tables, enum, indexes. Functions/triggers in 0002, RLS in 0003, seed in 0004.

create extension if not exists pgcrypto with schema extensions;

-- Security-definer helpers live here; never exposed via PostgREST.
create schema if not exists private;
grant usage on schema private to anon, authenticated;

-- Mirrors football-data.org statuses (lossless, superset-tolerant).
create type public.fixture_status as enum (
  'scheduled', 'timed', 'in_play', 'paused', 'finished',
  'suspended', 'postponed', 'cancelled', 'awarded'
);

-- Invite codes: 10 chars from an unambiguous alphabet (~49 bits of entropy).
create or replace function private.gen_invite_code()
returns text
language sql
volatile
set search_path = ''
as $$
  select string_agg(
    substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789',
           (get_byte(extensions.gen_random_bytes(1), 0) % 31) + 1, 1),
    '')
  from generate_series(1, 10);
$$;

-- sport is first-class: everything hangs off sports via competitions.
create table public.sports (
  id         uuid primary key default gen_random_uuid(),
  slug       text not null unique,
  name       text not null,
  created_at timestamptz not null default now()
);

create table public.competitions (
  id              uuid primary key default gen_random_uuid(),
  sport_id        uuid not null references public.sports (id),
  name            text not null,
  code            text not null,
  season          int,
  rules           jsonb not null default '{}',
  external_source text not null default 'football-data.org',
  external_id     text,
  last_synced_at  timestamptz,
  created_at      timestamptz not null default now(),
  unique (code, season),
  unique (external_source, external_id)
);

-- flag_code is ISO 3166-1 alpha-2 (text allows GB-ENG style). No crest column
-- on purpose: country flags only, never team crests.
create table public.teams (
  id             uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.competitions (id) on delete cascade,
  name           text not null,
  short_code     text,
  flag_code      text,
  ranking        int,
  external_id    bigint,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (competition_id, external_id)
);

-- home/away nullable: knockout slots are TBD until earlier rounds finish.
-- venue_city holds a city name only — never a stadium or sponsor name.
create table public.fixtures (
  id                    uuid primary key default gen_random_uuid(),
  competition_id        uuid not null references public.competitions (id) on delete cascade,
  home_id               uuid references public.teams (id),
  away_id               uuid references public.teams (id),
  kickoff_utc           timestamptz not null,
  venue_city            text,
  status                public.fixture_status not null default 'scheduled',
  home_score            smallint,
  away_score            smallint,
  stage                 text,
  group_name            text,
  matchday              smallint,
  score_detail          jsonb,
  external_id           bigint not null unique,
  external_last_updated timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index fixtures_comp_kickoff_idx on public.fixtures (competition_id, kickoff_utc);
create index fixtures_live_idx on public.fixtures (status)
  where status in ('timed', 'in_play', 'paused');

create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text not null,
  avatar_seed  text not null,
  points       int  not null default 0,
  streak       int  not null default 0,
  flex_tokens  int  not null default 0,
  pass_tier    text not null default 'free'
               check (pass_tier in ('free', 'plus', 'club')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index profiles_points_idx on public.profiles (points desc);

create table public.predictions (
  user_id        uuid not null references public.profiles (id) on delete cascade,
  fixture_id     uuid not null references public.fixtures (id) on delete cascade,
  home_pick      smallint not null check (home_pick between 0 and 30),
  away_pick      smallint not null check (away_pick between 0 and 30),
  locked_at      timestamptz,
  points_awarded smallint,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  primary key (user_id, fixture_id)
);
create index predictions_fixture_idx on public.predictions (fixture_id);
create index predictions_unscored_idx on public.predictions (fixture_id)
  where points_awarded is null;

create table public.leagues (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 60),
  owner_id    uuid not null references public.profiles (id) on delete cascade,
  invite_code text not null unique default private.gen_invite_code(),
  is_pod      boolean not null default false,
  created_at  timestamptz not null default now()
);

create table public.league_members (
  league_id uuid not null references public.leagues (id) on delete cascade,
  user_id   uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (league_id, user_id)
);
create index league_members_user_idx on public.league_members (user_id);

create table public.referrals (
  referrer_id  uuid not null references public.profiles (id) on delete cascade,
  joined_id    uuid not null references public.profiles (id) on delete cascade,
  points_given int  not null default 0,
  created_at   timestamptz not null default now(),
  primary key (joined_id),
  check (referrer_id <> joined_id)
);

create table public.platform_votes (
  id         uuid primary key default gen_random_uuid(),
  platform   text not null check (char_length(platform) <= 40),
  user_id    uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (user_id, platform)
);

-- Cron observability; service-role only.
create table public.sync_runs (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null,
  started_at  timestamptz not null default now(),
  finished_at timestamptz,
  ok          boolean,
  detail      jsonb
);
