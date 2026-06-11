import "server-only";
import { createClient } from "@supabase/supabase-js";

// Service-role client: bypasses RLS. Cron/scoring only — never import from
// client code (enforced by "server-only").
export function createAdminClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}
