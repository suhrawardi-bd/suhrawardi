import { NextResponse } from "next/server";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createAdminClient } from "@/lib/supabase/admin";
import { fdFetch } from "@/lib/football-data/client";
import { mapStatus } from "@/lib/football-data/mappers";
import type {
  FDMatchesResponse,
  FDTeamsResponse,
} from "@/lib/football-data/types";
import { venueCity } from "@/lib/data/venue-cities";
import { countryFlagCode } from "@/lib/data/country-codes";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

const TEAMS_REFRESH_MS = 24 * 60 * 60 * 1000;

type Competition = { id: string; code: string; external_id: string };
type RunDetail = Record<string, unknown>;

export async function GET(request: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const supabase = createAdminClient();

  // Every competition with an upstream id gets synced — football (and any
  // future sport) is configuration, not code.
  const { data: competitions, error } = await supabase
    .from("competitions")
    .select("id, code, external_id")
    .eq("external_source", "football-data.org")
    .not("external_id", "is", null);
  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  const results: RunDetail[] = [];
  for (const comp of (competitions ?? []) as Competition[]) {
    if (await teamsStale(supabase, comp)) {
      results.push(
        await recordRun(supabase, "teams", comp.code, () =>
          syncTeams(supabase, comp),
        ),
      );
    }
    results.push(
      await recordRun(supabase, "matches", comp.code, () =>
        syncMatches(supabase, comp),
      ),
    );
    await supabase
      .from("competitions")
      .update({ last_synced_at: new Date().toISOString() })
      .eq("id", comp.id);
  }

  const ok = results.every((r) => r.ok === true);
  return NextResponse.json({ ok, results }, { status: ok ? 200 : 502 });
}

// Wraps a sync phase in a sync_runs row so every cron tick is observable.
async function recordRun(
  supabase: SupabaseClient,
  kind: string,
  competition: string,
  fn: () => Promise<RunDetail>,
): Promise<RunDetail> {
  const { data: run } = await supabase
    .from("sync_runs")
    .insert({ kind, detail: { competition } })
    .select("id")
    .single();

  const finish = async (ok: boolean, detail: RunDetail) => {
    if (run?.id) {
      await supabase
        .from("sync_runs")
        .update({
          finished_at: new Date().toISOString(),
          ok,
          detail: { competition, ...detail },
        })
        .eq("id", run.id);
    }
  };

  try {
    const detail = await fn();
    await finish(true, detail);
    return { kind, competition, ok: true, ...detail };
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    await finish(false, { error: message });
    return { kind, competition, ok: false, error: message };
  }
}

// Squad lists barely change: refresh when empty or once a day. Keeps the
// normal run at a single upstream request.
async function teamsStale(
  supabase: SupabaseClient,
  comp: Competition,
): Promise<boolean> {
  const { count } = await supabase
    .from("teams")
    .select("*", { count: "exact", head: true })
    .eq("competition_id", comp.id);
  if (!count) return true;

  const { data } = await supabase
    .from("sync_runs")
    .select("finished_at")
    .eq("kind", "teams")
    .eq("ok", true)
    .contains("detail", { competition: comp.code })
    .order("finished_at", { ascending: false })
    .limit(1);

  const last = data?.[0]?.finished_at;
  return !last || Date.now() - new Date(last).getTime() > TEAMS_REFRESH_MS;
}

async function syncTeams(
  supabase: SupabaseClient,
  comp: Competition,
): Promise<RunDetail> {
  const { teams } = await fdFetch<FDTeamsResponse>(
    `/competitions/${comp.code}/teams`,
  );

  // Upstream `crest` is intentionally dropped: flags only, rendered from
  // flag_code by us.
  const rows = teams.map((t) => ({
    competition_id: comp.id,
    external_id: t.id,
    name: t.name,
    short_code: t.tla ?? null,
    flag_code: countryFlagCode(t.name),
  }));

  const { error } = await supabase
    .from("teams")
    .upsert(rows, { onConflict: "competition_id,external_id" });
  if (error) throw new Error(error.message);

  return {
    upserted: rows.length,
    unmappedFlags: rows.filter((r) => !r.flag_code).length,
  };
}

async function syncMatches(
  supabase: SupabaseClient,
  comp: Competition,
): Promise<RunDetail> {
  // One request covers the whole tournament (~104 matches, no pagination)
  // and heals any drift.
  const { matches } = await fdFetch<FDMatchesResponse>(
    `/competitions/${comp.code}/matches`,
  );

  const { data: teamRows, error: teamErr } = await supabase
    .from("teams")
    .select("id, external_id")
    .eq("competition_id", comp.id);
  if (teamErr) throw new Error(teamErr.message);
  const teamByExternal = new Map<number, string>(
    (teamRows ?? []).map((t) => [t.external_id as number, t.id as string]),
  );

  const { data: existing, error: exErr } = await supabase
    .from("fixtures")
    .select("external_id, external_last_updated")
    .eq("competition_id", comp.id);
  if (exErr) throw new Error(exErr.message);
  const lastUpdatedByExternal = new Map<number, string | null>(
    (existing ?? []).map((f) => [
      f.external_id as number,
      f.external_last_updated as string | null,
    ]),
  );

  let skipped = 0;
  let unmappedVenues = 0;
  let unknownStatuses = 0;
  const rows = [];

  for (const m of matches) {
    const prev = lastUpdatedByExternal.get(m.id);
    if (prev && new Date(prev).getTime() === new Date(m.lastUpdated).getTime()) {
      skipped += 1;
      continue;
    }

    const status = mapStatus(m.status);
    if (!status) unknownStatuses += 1;

    const city = venueCity(m.venue);
    if (m.venue && !city) unmappedVenues += 1;

    rows.push({
      competition_id: comp.id,
      external_id: m.id,
      // null team = TBD knockout slot; fills in once earlier rounds finish.
      home_id: m.homeTeam.id != null ? (teamByExternal.get(m.homeTeam.id) ?? null) : null,
      away_id: m.awayTeam.id != null ? (teamByExternal.get(m.awayTeam.id) ?? null) : null,
      kickoff_utc: m.utcDate,
      venue_city: city,
      status: status ?? "scheduled",
      home_score: m.score.fullTime.home,
      away_score: m.score.fullTime.away,
      stage: m.stage,
      group_name: m.group,
      matchday: m.matchday,
      // Full upstream score node (regularTime/extraTime/penalties/winner) so
      // the scoring step can choose its basis without a re-sync.
      score_detail: m.score,
      external_last_updated: m.lastUpdated,
    });
  }

  if (rows.length > 0) {
    const { error } = await supabase
      .from("fixtures")
      .upsert(rows, { onConflict: "external_id" });
    if (error) throw new Error(error.message);
  }

  return {
    total: matches.length,
    upserted: rows.length,
    skipped,
    unmappedVenues,
    unknownStatuses,
  };
}
