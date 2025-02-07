import { redirect, type LoaderFunctionArgs } from "@remix-run/node";
import { getSupabaseClient } from "~/utils/supabase.server";

export async function loader({ request }: LoaderFunctionArgs) {
  const supabase = getSupabaseClient();
  if (!supabase) {
    return redirect("/login");
  }

  const { data: { session } } = await supabase.auth.getSession();
  if (!session) {
    return redirect("/login");
  }

  return redirect("/dashboard");
}