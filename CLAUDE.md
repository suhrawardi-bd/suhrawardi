Project: CALLED IT! — multi-sport social prediction PWA. Sport #1: football.
Stack: Next.js (App Router) + Tailwind + Supabase + Vercel. PWA.

HARD RULES (never violate):
- Skill game: no betting, no odds anywhere, no stakes, no cash prizes. Points only.
- No FIFA/World Cup marks, no player photos/likenesses, no team crests.
  Country flags + city-named venues only.
- sport is a first-class column; football is a configuration, not hardcoded.
- Free tier never gates: sharing, leagues, pods.

DESIGN TOKENS (sticker-album festival):
- Fonts: Titan One (display), Nunito (body), IBM Plex Mono (codes)
- Colors: grass #1FA84F / #0E6B30, sun #FFD23F, tang #FF6B35,
  berry #E0356B, sky #2D1B5E / #4A2C8F, paper #FFFDF7, ink #21203A
- Language: white-border sticker cards, LOCKED stamp, share "receipts"

== Build (after plan approval, one step at a time) ==
1. Supabase schema with RLS:
   sports(id,name); competitions(id,sport_id,name,rules jsonb);
   teams(id,competition_id,name,flag_code,ranking);
   fixtures(id,competition_id,home_id,away_id,kickoff_utc,venue_city,
     status,home_score,away_score);
   profiles(id,display_name,avatar_seed,points,streak,flex_tokens,pass_tier);
   predictions(user_id,fixture_id,home_pick,away_pick,locked_at,
     points_awarded) unique(user_id,fixture_id);
   leagues(id,name,owner_id,invite_code,is_pod bool);
   league_members(league_id,user_id);
   referrals(referrer_id,joined_id,points_given);
   platform_votes(id,platform,created_at)
2. Vercel Cron route syncing football-data.org (free tier, WC)
   every 15 min, respecting 10 req/min. Guest-first anonymous auth.
3. Swipeable prediction deck, lock at kickoff, schedule view (✓/⚠️).
4. Scoring on final: exact 6 / winner+GD 4 / winner-or-draw 3.
5. Private leagues (invite code, WhatsApp link) + Random Pods (10, per matchday).
6. Canvas share card (flags, score, streak, receipt code, watermark) + Web Share API.
