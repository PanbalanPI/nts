import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") ?? "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};
const reply = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: cors });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { error: "Method not allowed." });

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) return reply(500, { error: "Admin function environment is incomplete." });

  const authorization = req.headers.get("Authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "");
  if (!token || token === authorization) return reply(401, { error: "Authentication required." });

  const authClient = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await authClient.auth.getUser(token);
  if (authError || !authData.user) return reply(401, { error: "Session is invalid or expired." });

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: actor, error: actorError } = await admin.from("profiles")
    .select("id, role, is_active").eq("id", authData.user.id).maybeSingle();
  if (actorError) return reply(500, { error: "Unable to validate command authority." });
  if (!actor || actor.role !== "ANO" || actor.is_active !== true) {
    return reply(403, { error: "Only an active ANO may provision command accounts." });
  }

  let input: Record<string, unknown>;
  try { input = await req.json(); } catch { return reply(400, { error: "Invalid JSON body." }); }
  if (input.action !== "invite") return reply(400, { error: "Unsupported admin action." });

  const email = typeof input.email === "string" ? input.email.trim().toLowerCase() : "";
  const fullName = typeof input.full_name === "string" ? input.full_name.trim() : "";
  const role = typeof input.role === "string" ? input.role : "";
  const serviceNumber = typeof input.service_number === "string" ? input.service_number.trim() : "";
  const rankTitle = typeof input.rank_title === "string" ? input.rank_title.trim() : "";
  const flightId = typeof input.flight_id === "string" && input.flight_id ? input.flight_id : null;
  const allowedRoles = ["RANKED_SENIOR", "FLIGHT_SENIOR", "SENIOR", "JUNIOR"];

  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return reply(400, { error: "A valid email address is required." });
  if (!fullName || fullName.length > 160) return reply(400, { error: "Full name is required (maximum 160 characters)." });
  if (!allowedRoles.includes(role)) return reply(403, { error: "Only non-ANO command roles can be invited through this screen." });
  if (serviceNumber.length > 80 || rankTitle.length > 100) return reply(400, { error: "Service number or rank title is too long." });

  if (flightId) {
    const { data: flight, error } = await admin.from("flights").select("id")
      .eq("id", flightId).eq("is_active", true).maybeSingle();
    if (error) return reply(500, { error: "Unable to validate flight assignment." });
    if (!flight) return reply(400, { error: "Selected flight does not exist or is inactive." });
  }

  const { data: invited, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, { data: { full_name: fullName } });
  if (inviteError || !invited.user) return reply(400, { error: inviteError?.message ?? "Unable to send invitation." });

  const { error: profileError } = await admin.from("profiles").update({
    full_name: fullName, service_number: serviceNumber || null, role,
    rank_title: rankTitle, flight_id: flightId, is_active: true,
  }).eq("id", invited.user.id);

  if (profileError) {
    await admin.auth.admin.updateUserById(invited.user.id, { ban_duration: "876000h" });
    return reply(500, { error: "Invitation was created but profile setup failed; account was disabled. Check the profile trigger and retry after fixing it." });
  }

  await admin.from("audit_events").insert({
    actor_id: actor.id, action: "ANO_INVITED_USER", object_type: "profiles",
    object_id: invited.user.id, metadata: { role, email, flight_id: flightId },
  });
  return reply(201, { success: true, user_id: invited.user.id, message: "Invitation sent. The user must accept it and set their password before signing in." });
});
