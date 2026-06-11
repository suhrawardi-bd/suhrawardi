# CALLED IT!

Multi-sport social prediction PWA — call the score, collect the points.
Skill game: no betting, no odds, no stakes. See `CLAUDE.md` for the hard
rules and build sequence.

Stack: Next.js (App Router) + Tailwind + Supabase + Vercel.

## Setup

```bash
npm install
cp .env.example .env.local   # fill in Supabase + football-data.org keys
```

### Database (Supabase)

```bash
supabase start          # local stack (needs Docker)
supabase db reset       # applies supabase/migrations/* + dev seed
supabase gen types typescript --local > types/database.ts
```

Anonymous sign-ins must be enabled (already on in `supabase/config.toml`
for local; enable in the dashboard for hosted projects).

No Supabase CLI/Docker around? Validate the schema against any Postgres:

```bash
createdb calledit
psql -d calledit -v ON_ERROR_STOP=1 \
  -f scripts/supabase-shim.sql \
  -f supabase/migrations/20260611000001_init.sql \
  -f supabase/migrations/20260611000002_functions.sql \
  -f supabase/migrations/20260611000003_rls.sql \
  -f supabase/migrations/20260611000004_seed_football.sql \
  -f supabase/seed.sql
psql -d calledit -f scripts/rls-smoke.sql   # prints RLS SMOKE TESTS PASSED
```

### Run

```bash
npm run dev
```

### Fixture sync

`vercel.json` schedules `GET /api/cron/sync-fixtures` every 15 minutes
(requires Vercel Pro for that frequency; on Hobby, trigger it from a GitHub
Actions schedule or pg_cron instead). Trigger manually:

```bash
curl -i -H "Authorization: Bearer $CRON_SECRET" \
  http://localhost:3000/api/cron/sync-fixtures
```

Each run uses at most 2 football-data.org requests (free tier allows
10/min) and records its outcome in the `sync_runs` table.
