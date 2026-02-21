import { createClient, SupabaseClient } from "@supabase/supabase-js";

let _serviceClient: SupabaseClient | null = null;

// Server-side only (service role, bypasses RLS)
export function getServiceSupabase(): SupabaseClient {
  if (_serviceClient) return _serviceClient;

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !key) {
    throw new Error("Missing NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }

  _serviceClient = createClient(url, key);
  return _serviceClient;
}
