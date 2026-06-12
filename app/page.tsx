"use client";

// Throwaway debug page proving auth + schema end-to-end; replaced by the
// prediction deck in build step 3.

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { useAuth } from "./providers";

export default function Home() {
  const { session, loading } = useAuth();
  const [displayName, setDisplayName] = useState<string | null>(null);
  const [fixtureCount, setFixtureCount] = useState<number | null>(null);

  useEffect(() => {
    if (!session) return;
    const supabase = createClient();

    supabase
      .from("profiles")
      .select("display_name")
      .eq("id", session.user.id)
      .single()
      .then(({ data }) => setDisplayName(data?.display_name ?? null));

    supabase
      .from("fixtures")
      .select("*", { count: "exact", head: true })
      .then(({ count }) => setFixtureCount(count));
  }, [session]);

  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-2 p-8">
      <h1 className="text-3xl font-bold">CALLED IT!</h1>
      {loading ? (
        <p>Connecting…</p>
      ) : session ? (
        <>
          <p>
            Signed in as guest{" "}
            <span className="font-semibold">{displayName ?? "…"}</span>
          </p>
          <p>
            {fixtureCount === null ? "Loading fixtures…" : `${fixtureCount} fixtures synced`}
          </p>
        </>
      ) : (
        <p>Could not start a guest session.</p>
      )}
    </main>
  );
}
