import { json, redirect, type LoaderFunctionArgs } from "@remix-run/node";
import { useLoaderData } from "@remix-run/react";
import { cn } from "~/utils/cn";
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

  // Fetch user's realms and hero data
  const [{ data: realms }, { data: hero }] = await Promise.all([
    supabase
      .from("realms")
      .select("*")
      .eq("created_by", session.user.id),
    supabase
      .from("heroes")
      .select("*")
      .eq("id", session.user.id)
      .single()
  ]);

  return json({ realms, hero });
}

export default function Dashboard() {
  const { realms, hero } = useLoaderData<typeof loader>();

  return (
    <div className="min-h-screen bg-[#1a1b26] bg-[url('/grid-bg.png')] bg-repeat">
      <div className="container mx-auto px-4 py-8">
        <header className="mb-8 flex justify-between items-center">
          <div>
            <h1 className="text-4xl font-pixel text-[#7aa2f7] mb-2">WELCOME BACK</h1>
            <p className="text-[#a9b1d6] font-pixel-text text-xl">{hero.display_name}</p>
          </div>
          <div className="flex items-center space-x-4">
            <div className="text-right">
              <p className="font-pixel-text text-[#a9b1d6]">COINS</p>
              <p className="font-pixel text-[#e0af68]">{hero.coins}</p>
            </div>
            <div className="w-12 h-12 bg-[#24283b] border-2 border-[#7aa2f7] rounded-lg flex items-center justify-center">
              <span className="text-[#e0af68] font-pixel">$</span>
            </div>
          </div>
        </header>

        {!realms?.length ? (
          <div className="bg-[#24283b] border-4 border-[#7aa2f7] rounded-lg shadow-neon p-8 text-center">
            <p className="text-[#a9b1d6] font-pixel-text text-xl mb-4">NO ACTIVE GAMES FOUND</p>
            <button
              className={cn(
                "px-6 py-3 rounded font-pixel text-sm",
                "bg-[#7aa2f7] text-[#1a1b26] border-b-4 border-[#2ac3de]",
                "hover:bg-[#2ac3de] transition-colors",
                "focus:outline-none focus:ring-2 focus:ring-[#7aa2f7] focus:ring-offset-2 focus:ring-offset-[#1a1b26]",
                "active:border-b-0 active:mt-1 active:mb-[-1px]"
              )}
            >
              NEW GAME
            </button>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {realms.map((realm) => (
              <div
                key={realm.id}
                className="bg-[#24283b] border-4 border-[#7aa2f7] rounded-lg shadow-neon p-6"
              >
                <div className="flex justify-between items-start mb-4">
                  <h2 className="text-2xl font-pixel text-[#7aa2f7]">
                    {realm.name}
                  </h2>
                  <div className="px-2 py-1 bg-[#1a1b26] rounded border border-[#7aa2f7]">
                    <p className="text-[#a9b1d6] font-pixel-text text-sm">
                      LVL 1
                    </p>
                  </div>
                </div>
                <div className="space-y-2 mb-4">
                  <div className="h-2 bg-[#1a1b26] rounded-full">
                    <div className="h-full w-1/3 bg-[#9ece6a] rounded-full"></div>
                  </div>
                  <p className="text-right text-[#9ece6a] font-pixel-text text-sm">
                    PROGRESS 33%
                  </p>
                </div>
                <button
                  className={cn(
                    "w-full px-4 py-3 rounded font-pixel text-sm",
                    "bg-[#7aa2f7] text-[#1a1b26] border-b-4 border-[#2ac3de]",
                    "hover:bg-[#2ac3de] transition-colors",
                    "focus:outline-none focus:ring-2 focus:ring-[#7aa2f7] focus:ring-offset-2 focus:ring-offset-[#1a1b26]",
                    "active:border-b-0 active:mt-1 active:mb-[-1px]"
                  )}
                >
                  CONTINUE
                </button>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}