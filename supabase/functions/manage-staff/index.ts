import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type Action =
  | { action: "invite"; email: string; full_name?: string; role?: "admin" | "support"; redirect_to?: string }
  | { action: "update_role"; user_id: string; role: "admin" | "support" }
  | { action: "deactivate"; user_id: string }
  | { action: "reactivate"; user_id: string };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Missing authorization" }, 200);

    // Verify caller
    const userClient = createClient(SUPABASE_URL, ANON, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData.user) return json({ error: "Unauthorized" }, 200);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
    const { data: roles } = await admin
      .from("user_roles")
      .select("role")
      .eq("user_id", userData.user.id);
    const isAdmin = roles?.some((r: any) => r.role === "admin");
    if (!isAdmin) return json({ error: "Forbidden" }, 200);

    const body = (await req.json()) as Action;

    if (body.action === "invite") {
      const email = String(body.email ?? "").trim().toLowerCase();
      const role = body.role ?? "support";
      const fullName = String(body.full_name ?? "").trim();
      if (!fullName) {
        return json({ error: "Full name required" }, 200);
      }
      if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        return json({ error: "Valid email required" }, 200);
      }
      if (role !== "admin" && role !== "support") {
        return json({ error: "Invalid role" }, 200);
      }
      const redirectTo = body.redirect_to ?? undefined;

      // Try invite. If user already exists, fall back to inserting role only.
      const { data: invited, error: invErr } = await admin.auth.admin.inviteUserByEmail(email, {
        redirectTo,
        data: { full_name: fullName },
      });
      let targetUserId: string | null = invited?.user?.id ?? null;

      if (invErr) {
        // Likely already exists — look it up
        const msg = invErr.message?.toLowerCase() ?? "";
        if (msg.includes("already") || msg.includes("registered") || msg.includes("exists")) {
          // Find user via listUsers (paged); first 1000 users
          const { data: list } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
          const found = list?.users.find((u) => (u.email ?? "").toLowerCase() === email);
          if (!found) return json({ error: "User exists but could not be located" }, 200);
          targetUserId = found.id;
          // Update their full_name in user_metadata (preserve existing metadata).
          const existingMeta = (found.user_metadata ?? {}) as Record<string, unknown>;
          await admin.auth.admin.updateUserById(targetUserId, {
            user_metadata: { ...existingMeta, full_name: fullName },
          });
        } else {
          return json({ error: invErr.message }, 200);
        }
      }
      if (!targetUserId) return json({ error: "Failed to create user" }, 200);

      // Upsert role: clear other staff roles for this user, then insert chosen role
      await admin.from("user_roles").delete().eq("user_id", targetUserId).in("role", ["admin", "support"]);
      const { error: roleErr } = await admin.from("user_roles").insert({ user_id: targetUserId, role });
      if (roleErr) return json({ error: roleErr.message }, 200);

      return json({ success: true, user_id: targetUserId });
    }

    if (body.action === "update_role") {
      if (!body.user_id) return json({ error: "user_id required" }, 200);
      if (body.role !== "admin" && body.role !== "support") return json({ error: "Invalid role" }, 200);
      if (body.user_id === userData.user.id && body.role !== "admin") {
        return json({ error: "You cannot remove your own admin role" }, 200);
      }
      await admin.from("user_roles").delete().eq("user_id", body.user_id).in("role", ["admin", "support"]);
      const { error } = await admin.from("user_roles").insert({ user_id: body.user_id, role: body.role });
      if (error) return json({ error: error.message }, 200);
      return json({ success: true });
    }

    if (body.action === "deactivate") {
      if (!body.user_id) return json({ error: "user_id required" }, 200);
      if (body.user_id === userData.user.id) return json({ error: "You cannot deactivate yourself" }, 200);
      // 100 years effectively disables the account
      const { error } = await admin.auth.admin.updateUserById(body.user_id, {
        ban_duration: `${100 * 365 * 24}h`,
      });
      if (error) return json({ error: error.message }, 200);
      return json({ success: true });
    }

    if (body.action === "reactivate") {
      if (!body.user_id) return json({ error: "user_id required" }, 200);
      const { error } = await admin.auth.admin.updateUserById(body.user_id, {
        ban_duration: "none",
      });
      if (error) return json({ error: error.message }, 200);
      return json({ success: true });
    }

    return json({ error: "Unknown action" }, 200);
  } catch (e) {
    return json({ error: (e as Error).message }, 200);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
