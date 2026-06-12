"use client";

import {
  createContext,
  useContext,
  useEffect,
  useRef,
  useState,
} from "react";
import type { Session } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";

type AuthState = { session: Session | null; loading: boolean };

const AuthContext = createContext<AuthState>({ session: null, loading: true });

export function useAuth() {
  return useContext(AuthContext);
}

// Guest-first: any visitor without a session gets an anonymous one. The DB
// trigger on auth.users creates their profile, so they can predict, join
// leagues and land in pods immediately — no signup wall.
export function Providers({ children }: { children: React.ReactNode }) {
  const [state, setState] = useState<AuthState>({
    session: null,
    loading: true,
  });
  const signingIn = useRef(false);

  useEffect(() => {
    const supabase = createClient();

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setState({ session, loading: false });
    });

    supabase.auth.getSession().then(async ({ data: { session } }) => {
      if (session) {
        setState({ session, loading: false });
        return;
      }
      // Ref guard: React strict mode mounts effects twice in dev.
      if (signingIn.current) return;
      signingIn.current = true;
      const { data, error } = await supabase.auth.signInAnonymously();
      if (error) {
        console.error("anonymous sign-in failed", error);
        setState({ session: null, loading: false });
        return;
      }
      setState({ session: data.session, loading: false });
    });

    return () => subscription.unsubscribe();
  }, []);

  return <AuthContext.Provider value={state}>{children}</AuthContext.Provider>;
}
