import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function response(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return response({ error: "Method not allowed" }, 405);
  }

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return response({ error: "Authentication required" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    console.error("Missing required Supabase environment variables");
    return response({ error: "Account deletion is not configured" }, 500);
  }

  const token = authorization.slice("Bearer ".length);
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    // Validate the caller's JWT; never accept a user ID supplied by the client.
    const { data: authData, error: authError } = await userClient.auth.getUser(token);
    const user = authData.user;
    if (authError || !user) {
      return response({ error: "Invalid or expired session" }, 401);
    }

    // Remove user-owned storage objects. Supabase Storage folders are virtual,
    // so walk nested folders and paginate instead of assuming one flat page.
    async function removeUserFolder(bucketName: string, folder: string) {
      const storage = admin.storage.from(bucketName);
      const pending = [folder];
      while (pending.length > 0) {
        const current = pending.pop()!;
        let offset = 0;
        while (true) {
          const { data, error } = await storage.list(current, {
            limit: 100,
            offset,
            sortBy: { column: "name", order: "asc" },
          });
          if (error) throw new Error(`Storage listing failed for ${bucketName}: ${error.message}`);
          if (!data || data.length === 0) break;

          const files = data.filter((item) => item.id !== null);
          const folders = data.filter((item) => item.id === null);
          for (const item of folders) {
            pending.push(`${current}/${item.name}`);
          }

          if (files.length > 0) {
            const paths = files.map((item) => `${current}/${item.name}`);
            const { error: removeError } = await storage.remove(paths);
            if (removeError) {
              throw new Error(`Storage removal failed for ${bucketName}: ${removeError.message}`);
            }
          }

          if (data.length < 100) break;
          offset += data.length;
        }
      }
    }

    // These are the user-scoped buckets present in this repository's schema:
    // avatars, chat media (messages), and the private hall-of-fame gallery.
    for (const bucket of ["avatars", "messages", "hall-of-fame"]) {
      await removeUserFolder(bucket, user.id);
    }

    // Several legacy quiz tables intentionally have user_id columns without
    // an auth.users FK. Delete their rows explicitly; otherwise deleting the
    // Auth user would leave identifiable quiz history behind.
    const userOwnedTables = [
      "quiz_answers",
      "quiz_sessions",
      "user_answers",
      "user_quiz_attempts",
      "error_notebook",
    ] as const;

    for (const table of userOwnedTables) {
      const { error } = await admin.from(table).delete().eq("user_id", user.id);
      if (error) {
        console.error(`Could not delete account rows from ${table}`, error);
        return response({ error: "Could not delete all account data" }, 500);
      }
    }

    // Rows linked by ON DELETE CASCADE (profiles, notifications, device_tokens,
    // hall_of_fame_photos, notes, plans, devices, and relationship_pairs) are
    // removed by the Auth deletion. The profile relationship FK is expected to
    // clear the other participant's paired_with reference via ON DELETE SET NULL.
    const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
    if (deleteError) {
      console.error("Auth user deletion failed", deleteError);
      return response({ error: "Account data could not be fully deleted" }, 500);
    }

    return response({ success: true });
  } catch (error) {
    console.error("Unexpected account deletion error", error);
    return response({ error: "Account deletion failed" }, 500);
  }
});
