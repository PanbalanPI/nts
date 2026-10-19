import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";

const cors = {
  "Access-Control-Allow-Origin": Deno.env.get("UNIT_MANAGER_ALLOWED_ORIGIN") ?? "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};
const response = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: cors });
const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

function tempPassword() {
  const bytes = crypto.getRandomValues(new Uint8Array(24));
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%";
  const raw = Array.from(bytes, b => alphabet.charAt(b % alphabet.length)).join("");
  return raw + "aA7!";
}
function safeRegimental(value: unknown) {
  const valueText = String(value ?? "").trim();
  if (!/^[A-Za-z0-9-]{3,40}$/.test(valueText)) throw new Error("Regimental number must be 3–40 letters, digits or hyphens.");
  return valueText;
}
async function authUser(req: Request) {
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) throw new Error("Authentication required.");
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) throw new Error("Your session is invalid or expired.");
  return data.user;
}
async function requireAdmin(userId: string) {
  const { data, error } = await admin.from("um_user_roles").select("unit_id,role").eq("user_id", userId).eq("role", "admin").maybeSingle();
  if (error || !data) throw new Error("Only a unit admin may perform this action.");
  const { data: profile, error: profileError } = await admin.from("um_profiles").select("id,unit_id,full_name,is_active").eq("user_id", userId).eq("unit_id", data.unit_id).maybeSingle();
  if (profileError || !profile?.is_active) throw new Error("The admin profile is inactive or unavailable.");
  return { unitId: data.unit_id as string, profile };
}

Deno.serve(async req => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return response({ error: "POST required." }, 405);
  try {
    const body = await req.json();
    const action = String(body.action ?? "");
    if (action === "bootstrap") {
      const secret = Deno.env.get("UNIT_MANAGER_BOOTSTRAP_SECRET");
      if (!secret || typeof body.bootstrap_secret !== "string" || body.bootstrap_secret.length < 20) {
        return response({ error: "Bootstrap is not configured. Set UNIT_MANAGER_BOOTSTRAP_SECRET in Supabase Edge Function secrets." }, 503);
      }
      const [providedHash, expectedHash] = await Promise.all([
        crypto.subtle.digest("SHA-256", new TextEncoder().encode(body.bootstrap_secret)),
        crypto.subtle.digest("SHA-256", new TextEncoder().encode(secret)),
      ]);
      const a = new Uint8Array(providedHash), b = new Uint8Array(expectedHash);
      if (a.length !== b.length || a.some((v, i) => v !== b[i])) return response({ error: "Invalid bootstrap secret." }, 403);
      const { count, error: countError } = await admin.from("um_user_roles").select("id", { count: "exact", head: true });
      if (countError) throw countError;
      if ((count ?? 0) > 0) return response({ error: "Bootstrap is locked because a role assignment already exists. Ask an existing unit admin to invite users." }, 409);
      const email = String(body.email ?? "").trim().toLowerCase();
      const fullName = String(body.full_name ?? "").trim();
      const unitName = String(body.unit_name ?? "").trim();
      const unitCode = String(body.unit_code ?? "").trim().toUpperCase();
      const password = String(body.password ?? "");
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || fullName.length < 2 || unitName.length < 2 || !/^[A-Z0-9-]{2,20}$/.test(unitCode) || password.length < 12) {
        return response({ error: "Provide a valid email, full name, unit name/code and an initial password of at least 12 characters." }, 400);
      }
      const { data: unit, error: unitError } = await admin.from("um_units").insert({ name: unitName, code: unitCode, timezone: "Asia/Kolkata" }).select("id").single();
      if (unitError) throw unitError;
      const { data: created, error: userError } = await admin.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: {} });
      if (userError || !created.user) {
        await admin.from("um_units").delete().eq("id", unit.id);
        throw userError ?? new Error("Could not create admin account.");
      }
      const userId = created.user.id;
      const { error: profileError } = await admin.from("um_profiles").insert({ user_id: userId, unit_id: unit.id, full_name: fullName, email, force_password_change: false, is_active: true });
      if (profileError) { await admin.auth.admin.deleteUser(userId); await admin.from("um_units").delete().eq("id", unit.id); throw profileError; }
      const { error: roleError } = await admin.from("um_user_roles").insert({ user_id: userId, unit_id: unit.id, role: "admin" });
      if (roleError) { await admin.auth.admin.deleteUser(userId); await admin.from("um_units").delete().eq("id", unit.id); throw roleError; }
      return response({ ok: true, message: "Unit and first admin created. Sign in with the admin email and password.", unit_id: unit.id });
    }

    const user = await authUser(req);
    if (action === "change_password") {
      const currentPassword = String(body.current_password ?? "");
      const newPassword = String(body.new_password ?? "");
      if (newPassword.length < 12) return response({ error: "New password must contain at least 12 characters." }, 400);
      const authClient = createClient(supabaseUrl, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
      const { data: verified, error: verifyError } = await authClient.auth.signInWithPassword({ email: user.email ?? "", password: currentPassword });
      if (verifyError || verified.user?.id !== user.id) return response({ error: "Current password is incorrect." }, 403);
      const { error: passwordError } = await admin.auth.admin.updateUserById(user.id, { password: newPassword });
      if (passwordError) throw passwordError;
      const { error: profileError } = await admin.from("um_profiles").update({ force_password_change: false }).eq("user_id", user.id);
      if (profileError) throw profileError;
      return response({ ok: true, message: "Password changed. You can now access the unit workspace." });
    }

    const { unitId } = await requireAdmin(user.id);
    if (action === "seed_demo") {
      const { data, error } = await admin.rpc("um_seed_demo");
      if (error) throw error;
      return response({ ok: true, data });
    }
    if (action === "invite") {
      const role = String(body.role ?? "");
      if (!["officer", "senior", "cadet"].includes(role)) return response({ error: "Only officer, senior or cadet roles can be provisioned here." }, 400);
      const fullName = String(body.full_name ?? "").trim();
      const flightId = body.flight_id ? String(body.flight_id) : null;
      if (fullName.length < 2) return response({ error: "Full name is required." }, 400);
      if (flightId) {
        const { data: flight, error } = await admin.from("um_flights").select("id").eq("id", flightId).eq("unit_id", unitId).eq("is_active", true).maybeSingle();
        if (error || !flight) return response({ error: "Selected flight is not active in this unit." }, 400);
      }
      let email = String(body.email ?? "").trim().toLowerCase();
      let regimentalNo: string | null = null;
      let password: string | null = null;
      if (role === "cadet") {
        regimentalNo = safeRegimental(body.regimental_no);
        email = regimentalNo.toLowerCase() + "@unit.local";
        password = tempPassword();
      } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        return response({ error: "A valid email address is required for officers and seniors." }, 400);
      }
      let userId: string;
      if (role === "cadet") {
        const { data, error } = await admin.auth.admin.createUser({ email, password: password!, email_confirm: true });
        if (error || !data.user) throw error ?? new Error("Could not create cadet account.");
        userId = data.user.id;
      } else {
        const { data, error } = await admin.auth.admin.inviteUserByEmail(email, { data: {} });
        if (error || !data.user) throw error ?? new Error("Could not send invitation.");
        userId = data.user.id;
      }
      const { error: profileError } = await admin.from("um_profiles").insert({ user_id: userId, unit_id: unitId, flight_id: flightId, full_name: fullName, email, force_password_change: role === "cadet", is_active: true });
      if (profileError) { await admin.auth.admin.deleteUser(userId); throw profileError; }
      const { error: roleError } = await admin.from("um_user_roles").insert({ user_id: userId, unit_id: unitId, role, granted_by: user.id });
      if (roleError) { await admin.auth.admin.deleteUser(userId); throw roleError; }
      if (regimentalNo) {
        const { error: cadetError } = await admin.from("um_cadets").insert({ unit_id: unitId, user_id: userId, flight_id: flightId, regimental_no: regimentalNo, full_name: fullName, year_of_training: Number(body.year_of_training ?? 1), rank: String(body.rank ?? "Cadet"), wing: "AIR" });
        if (cadetError) { await admin.from("um_user_roles").delete().eq("user_id", userId).eq("unit_id", unitId); await admin.from("um_profiles").delete().eq("user_id", userId).eq("unit_id", unitId); await admin.auth.admin.deleteUser(userId); throw cadetError; }
      }
      return response({ ok: true, message: role === "cadet" ? "Cadet account created. Share the temporary password securely and require a change at first login." : "Invitation email sent.", username: role === "cadet" ? regimentalNo : undefined, email, temporary_password: password ?? undefined });
    }
    if (action === "update_member") {
      const targetUserId = String(body.user_id ?? "");
      const nextRole = String(body.role ?? "");
      const isActive = body.is_active === true;
      const flightId = body.flight_id ? String(body.flight_id) : null;
      if (!targetUserId || !["officer","senior","cadet"].includes(nextRole)) return response({ error: "Choose an existing member and a supported role." }, 400);
      if (targetUserId === user.id) return response({ error: "You cannot change your own access from this screen." }, 403);
      const { data: targetRole, error: targetRoleError } = await admin.from("um_user_roles").select("role").eq("user_id", targetUserId).eq("unit_id", unitId).maybeSingle();
      if (targetRoleError || !targetRole || targetRole.role === "admin") return response({ error: "This member cannot be changed through routine user management." }, 403);
      if (flightId) {
        const { data: flight, error } = await admin.from("um_flights").select("id").eq("id", flightId).eq("unit_id", unitId).eq("is_active", true).maybeSingle();
        if (error || !flight) return response({ error: "Selected flight is not active in this unit." }, 400);
      }
      const { error: profileUpdateError } = await admin.from("um_profiles").update({ flight_id: flightId, is_active: isActive }).eq("user_id", targetUserId).eq("unit_id", unitId);
      if (profileUpdateError) throw profileUpdateError;
      const { error: roleUpdateError } = await admin.from("um_user_roles").update({ role: nextRole, granted_by: user.id }).eq("user_id", targetUserId).eq("unit_id", unitId);
      if (roleUpdateError) throw roleUpdateError;
      const { error: cadetUpdateError } = await admin.from("um_cadets").update({ flight_id: flightId, status: isActive ? "ACTIVE" : "INACTIVE" }).eq("user_id", targetUserId).eq("unit_id", unitId);
      if (cadetUpdateError) throw cadetUpdateError;
      return response({ ok: true, message: "Member access and flight assignment updated." });
    }
    return response({ error: "Unsupported action." }, 400);
  } catch (error) {
    console.error("unit-manager-admin-users:", error);
    return response({ error: error instanceof Error ? error.message : "Unexpected server error." }, 400);
  }
});
