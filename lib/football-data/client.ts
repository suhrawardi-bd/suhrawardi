import "server-only";

// Default to the v4 base. Strip trailing slashes so a misconfigured
// FOOTBALL_DATA_BASE_URL (e.g. ".../v4/") can't produce a double slash —
// football-data.org rejects that with "Invalid path specified in request URL".
const BASE_URL = (
  process.env.FOOTBALL_DATA_BASE_URL ?? "https://api.football-data.org/v4"
).replace(/\/+$/, "");

// Cap waits so a sync run never exceeds the route's maxDuration; with ≤2
// requests per run we stay far under the free tier's 10 req/min anyway and
// a skipped cycle self-heals 15 minutes later.
const MAX_WAIT_MS = 30_000;

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function resetWaitMs(res: Response): number {
  const reset = Number(res.headers.get("X-RequestCounter-Reset") ?? "60");
  return Math.min(Math.max(reset, 1) * 1000, MAX_WAIT_MS);
}

// .env.example and the docs use FOOTBALL_DATA_API_TOKEN, but FOOTBALL_DATA_TOKEN
// is an easy slip — accept either so a misnamed secret doesn't silently break.
function readToken(): string | undefined {
  return (
    process.env.FOOTBALL_DATA_API_TOKEN ?? process.env.FOOTBALL_DATA_TOKEN
  );
}

// Single entry point for upstream calls. Sequential by design — never call
// in parallel. Honors the per-minute budget via the rate-limit headers and
// retries a 429 once before giving up.
export async function fdFetch<T>(path: string): Promise<T> {
  const token = readToken();
  if (!token) {
    throw new Error(
      "football-data token missing: set FOOTBALL_DATA_API_TOKEN (or FOOTBALL_DATA_TOKEN)",
    );
  }

  // Guard against an empty/missing path segment (e.g. a competition row with a
  // blank code), which would yield ".../competitions//matches".
  const normalizedPath = path.startsWith("/") ? path : `/${path}`;
  const url = `${BASE_URL}${normalizedPath}`;

  // The token rides in the X-Auth-Token header, not the URL, so logging the
  // full URL leaks nothing — and it pinpoints a malformed base or path.
  console.log(`[football-data] GET ${url} (X-Auth-Token: ***redacted***)`);

  const doFetch = () =>
    fetch(url, {
      headers: { "X-Auth-Token": token },
      cache: "no-store",
    });

  let res = await doFetch();
  if (res.status === 429) {
    await sleep(resetWaitMs(res));
    res = await doFetch();
  }
  if (!res.ok) {
    // Surface the upstream body so errors like "Invalid path specified in
    // request URL" are visible alongside the exact URL we sent.
    const body = await res.text().catch(() => "");
    console.error(
      `[football-data] ${res.status} for ${url} :: ${body.slice(0, 300)}`,
    );
    throw new Error(
      `football-data GET ${url} responded ${res.status}: ${body.slice(0, 200)}`,
    );
  }

  const remaining = Number(
    res.headers.get("X-Requests-Available-Minute") ?? "10",
  );
  if (remaining < 2) {
    await sleep(resetWaitMs(res));
  }

  return (await res.json()) as T;
}
