import { json, redirect, type ActionFunctionArgs } from "@remix-run/node";
import { Form, Link, useActionData } from "@remix-run/react";
import { cn } from "~/utils/cn";
import { getSupabaseClient, isSupabaseConfigured } from "~/utils/supabase.server";

export async function action({ request }: ActionFunctionArgs) {
  if (!isSupabaseConfigured()) {
    return json(
      { error: "Please connect to Supabase using the 'Connect to Supabase' button in the top right corner." },
      { status: 400 }
    );
  }

  const supabase = getSupabaseClient();
  if (!supabase) {
    return json(
      { error: "Database connection not available" },
      { status: 500 }
    );
  }

  const formData = await request.formData();
  const email = formData.get("email") as string;
  const password = formData.get("password") as string;

  try {
    const { error, data: { session } } = await supabase.auth.signInWithPassword({
      email,
      password,
    });

    if (error) {
      return json({ error: error.message }, { status: 400 });
    }

    if (session) {
      return redirect("/dashboard");
    }

    return json({ error: "Login failed" }, { status: 400 });
  } catch (error) {
    console.error("Login error:", error);
    return json(
      { error: "An unexpected error occurred. Please try again." },
      { status: 500 }
    );
  }
}

export default function Login() {
  const actionData = useActionData<typeof action>();

  return (
    <div className="min-h-screen bg-[#1a1b26] bg-[url('/grid-bg.png')] bg-repeat flex items-center justify-center px-4">
      <div className="w-full max-w-md">
        <div className="bg-[#24283b] border-4 border-[#7aa2f7] rounded-lg shadow-neon p-8">
          <div className="text-center mb-8">
            <h1 className="text-4xl font-pixel text-[#7aa2f7] mb-2 tracking-wide">
              CHOREBOARD
            </h1>
            <p className="text-[#a9b1d6] font-pixel-text text-xl">INSERT CREDENTIALS TO CONTINUE</p>
          </div>

          <Form method="post" className="space-y-6">
            {actionData?.error && (
              <div className="bg-[#f7768e]/20 border-2 border-[#f7768e] text-[#f7768e] px-4 py-2 rounded font-pixel-text">
                {actionData.error}
              </div>
            )}

            <div>
              <label htmlFor="email" className="block text-sm font-pixel text-[#a9b1d6] mb-2">
                EMAIL ADDRESS
              </label>
              <input
                type="email"
                id="email"
                name="email"
                required
                className={cn(
                  "w-full px-4 py-2 rounded border-2",
                  "bg-[#1a1b26] text-[#a9b1d6] border-[#7aa2f7]",
                  "focus:outline-none focus:ring-2 focus:ring-[#7aa2f7] focus:border-[#7aa2f7]",
                  "placeholder:text-[#565f89] font-pixel-text"
                )}
                placeholder="player@email.com"
              />
            </div>

            <div>
              <label htmlFor="password" className="block text-sm font-pixel text-[#a9b1d6] mb-2">
                PASSWORD
              </label>
              <input
                type="password"
                id="password"
                name="password"
                required
                className={cn(
                  "w-full px-4 py-2 rounded border-2",
                  "bg-[#1a1b26] text-[#a9b1d6] border-[#7aa2f7]",
                  "focus:outline-none focus:ring-2 focus:ring-[#7aa2f7] focus:border-[#7aa2f7]",
                  "placeholder:text-[#565f89] font-pixel-text"
                )}
                placeholder="••••••••"
              />
            </div>

            <button
              type="submit"
              className={cn(
                "w-full px-4 py-3 rounded font-pixel text-sm",
                "bg-[#7aa2f7] text-[#1a1b26] border-b-4 border-[#2ac3de]",
                "hover:bg-[#2ac3de] transition-colors",
                "focus:outline-none focus:ring-2 focus:ring-[#7aa2f7] focus:ring-offset-2 focus:ring-offset-[#1a1b26]",
                "active:border-b-0 active:mt-1 active:mb-[-1px]"
              )}
            >
              START GAME
            </button>

            <div className="text-center">
              <Link
                to="/signup"
                className="text-[#7aa2f7] hover:text-[#2ac3de] font-pixel-text text-lg"
              >
                NEW PLAYER? REGISTER →
              </Link>
            </div>
          </Form>
        </div>
      </div>
    </div>
  );
}