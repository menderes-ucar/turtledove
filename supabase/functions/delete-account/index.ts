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

    // Read the profile only to detach the other participant and clean this
    // user's avatar objects. The Auth user ID remains the source of identity.
    const { data: profile, error: profileError } = await admin
      .from("profiles")
      .select("paired_with")
      .eq("id", user.id)
      .maybeSingle();

    if (profileError) {
      console.error("Could not load account profile", profileError);
      return response({ error: "Could not prepare account deletion" }, 500);
    }

    // Do not leave the partner profile pointing at a deleted account.
    if (profile?.paired_with) {
      const { error: detachError } = await admin
        .from("profiles")
        .update({ paired_with: null })
        .eq("id", profile.paired_with)
        .eq("paired_with", user.id);
      if (detachError) {
        console.error("Could not detach partner profile", detachError);
        return response({ error: "Could not detach the paired account" }, 500);
      }
    }

    // Avatar uploads use avatars/<auth-user-id>/<filename>.
    // Remove every object in that user's avatar folder before deleting Auth.
    const bucket = admin.storage.from("avatars");
    const { data: avatarObjects, error: listError } = await bucket.list(user.id, {
      limit: 1000,
      offset: 0,
    });
    if (listError) {
      console.error("Could not list account avatar objects", listError);
      return response({ error: "Could not remove account files" }, 500);
    }

    const objectNames = (avatarObjects ?? [])
      .filter((item) => item.id !== null)
      .map((item) => `${user.id}/${item.name}`);

    if (objectNames.length > 0) {
      const { error: removeError } = await bucket.remove(objectNames);
      if (removeError) {
        console.error("Could not remove account avatar objects", removeError);
        return response({ error: "Could not remove account files" }, 500);
      }
    }

    // The database must define ON DELETE CASCADE foreign keys for all
    // user-owned rows. If a restrictive FK exists, this fails closed instead
    // of reporting success while leaving a partially deleted account.
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
