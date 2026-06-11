import "server-only";

const BASE_URL =
  process.env.FOOTBALL_DATA_BASE_URL ?? "https://api.football-data.org/v4";

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

// Single entry point for upstream calls. Sequential by design — never call
// in parallel. Honors the per-minute budget via the rate-limit headers and
// retries a 429 once before giving up.
export async function fdFetch<T>(path: string): Promise<T> {
  const token = process.env.FOOTBALL_DATA_API_TOKEN;
  if (!token) throw new Error("FOOTBALL_DATA_API_TOKEN is not set");

  const doFetch = () =>
    fetch(`${BASE_URL}${path}`, {
      headers: { "X-Auth-Token": token },
      cache: "no-store",
    });

  let res = await doFetch();
  if (res.status === 429) {
    await sleep(resetWaitMs(res));
    res = await doFetch();
  }
  if (!res.ok) {
    throw new Error(`football-data ${path} responded ${res.status}`);
  }

  const remaining = Number(
    res.headers.get("X-Requests-Available-Minute") ?? "10",
  );
  if (remaining < 2) {
    await sleep(resetWaitMs(res));
  }

  return (await res.json()) as T;
}
