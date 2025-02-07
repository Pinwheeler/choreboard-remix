import { createClient } from "@supabase/supabase-js";
import { Database } from "~/types/supabase";

let supabase: ReturnType<typeof createClient<Database>> | null = null;

// Helper to check if Supabase is configured
export const isSupabaseConfigured = () => {
  return Boolean(process.env.SUPABASE_URL && process.env.SUPABASE_ANON_KEY);
};

// Create client only if configured
export const getSupabaseClient = () => {
  if (!isSupabaseConfigured()) {
    return null;
  }

  if (!supabase) {
    supabase = createClient<Database>(
      process.env.SUPABASE_URL!,
      process.env.SUPABASE_ANON_KEY!,
      {
        auth: {
          autoRefreshToken: true,
          persistSession: true,
        },
      }
    );
  }

  return supabase;
};