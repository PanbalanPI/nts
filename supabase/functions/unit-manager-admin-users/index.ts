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
  return Array.from(bytes, b => alphabet.charAt(b % alphabet.length)).join("") + "aA7!";
}
function safeRegimental(value: unknown) {
  const valueText = String(value ?? "").trim();
  if (!/^[A-Za-z0-9-]{3,40}$/.test(valueText)) throw new Error("Regimental number must be 3–40 letters, digits or hyphens.");
  return valueText;
}
function safeUnitCode(value: unknown) {
  const code = String(value ?? "").trim().toUpperCase();
  if (!/^[A-Z0-9-]{2,20}$/.test(code)) throw new Error("Unit code must be 2–20 letters, digits or hyphens.");
  return code;
}
async function authUser(req: Request) {
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) throw new Error("Authentication required.");
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) throw new Error("Your session is invalid or expired.");
  return data.user;
}
async function requireUnitAdmin(userId: string) {
  const { data: role, error: roleError } = await admin.from("um_user_roles")
    .select("unit_id,role").eq("user_id", userId).eq("role", "admin").maybeSingle();
  if (roleError || !role) throw new Error("Only the ANO or an approved delegated administrator may perform this action.");
  const { data: profile, error: profileError } = await admin.from("um_profiles")
    .select("id,user_id,unit_id,full_name,is_active,access_level")
    .eq("user_id", userId).eq("unit_id", role.unit_id).maybeSingle();
  if (profileError || !profile?.is_active || !["ano", "unit_admin"].includes(profile.access_level)) {
    throw new Error("Your unit administrator access is inactive or unavailable.");
  }
  return { unitId: role.unit_id as string, profile };
}
async function requestUnit(body: Record<string, unknown>) {
  const regimentalNo = safeRegimental(body.regimental_no);
  const unitCode = safeUnitCode(body.unit_code);
  const fullName = String(body.full_name ?? "").trim();
  const rankTitle = String(body.rank_title ?? "").trim();
  const appointment = String(body.appointment ?? "").trim() || null;
  const unitName = String(body.unit_name ?? "").trim();
  const password = String(body.password ?? "");
  const timezone = String(body.timezone ?? "Asia/Kolkata").trim() || "Asia/Kolkata";
  if (fullName.length < 2 || fullName.length > 160) throw new Error("Enter the applicant's full name.");
  if (rankTitle.length < 2 || rankTitle.length > 100) throw new Error("Enter the applicant's NCC rank.");
  if (unitName.length < 2 || unitName.length > 120) throw new Error("Enter a valid unit name.");
  if (password.length < 12) throw new Error("Password must contain at least 12 characters.");
  const email = regimentalNo.toLowerCase() + "@unit.local";
  const { data: existingUnit } = await admin.from("um_units").select("id").ilike("code", unitCode).maybeSingle();
  if (existingUnit) throw new Error("A unit with this code already exists.");
  const { data: existingRequest } = await admin.from("um_unit_registration_requests")
    .select("id").ilike("unit_code", unitCode).eq("status", "pending").maybeSingle();
  if (existingRequest) throw new Error("A registration request for this unit code is already pending.");
  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email, password, email_confirm: true, user_metadata: { full_name: fullName, registration_pending: true },
  });
  if (createError || !created.user) throw createError ?? new Error("Could not create applicant account.");
  const { error: requestError } = await admin.from("um_unit_registration_requests").insert({
    applicant_user_id: created.user.id, full_name: fullName, email, regimental_no: regimentalNo,
    rank_title: rankTitle, appointment, unit_name: unitName, unit_code: unitCode, timezone, status: "pending",
  });
  if (requestError) {
    await admin.auth.admin.deleteUser(created.user.id);
    throw requestError;
  }
  return response({ ok: true, status: "pending", message: "Unit registration submitted. Your account will receive unit access only after Platform Super Admin approval." }, 201);
}

Deno.serve(async req => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return response({ error: "POST required." }, 405);
  try {
    const body = await req.json() as Record<string, unknown>;
    const action = String(body.action ?? "");

    if (action === "request_unit") return await requestUnit(body);

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
      return response({ ok: true, message: "Password changed." });
    }

    if (action === "review_unit_registration") {
      const { data: superRole, error: superError } = await admin.from("um_platform_roles")
        .select("role").eq("user_id", user.id).eq("role", "super_admin").maybeSingle();
      if (superError || !superRole) return response({ error: "Only the Platform Super Admin can review unit registrations." }, 403);
      const requestId = String(body.request_id ?? "");
      const decision = String(body.decision ?? "");
      const reason = String(body.reason ?? "");
      if (!requestId || !["approve", "reject"].includes(decision)) return response({ error: "Choose a valid request and decision." }, 400);
      const { data, error } = await admin.rpc("um_review_unit_registration", {
        p_request_id: requestId, p_decision: decision, p_reason: reason, p_reviewer: user.id,
      });
      if (error) throw error;
      return response({ ok: true, data, message: decision === "approve" ? "Unit approved and ANO access activated." : "Registration rejected." });
    }

    const { unitId, profile } = await requireUnitAdmin(user.id);

    if (action === "set_unit_admin") {
      if (profile.access_level !== "ano") return response({ error: "Only the ANO can grant or revoke delegated administrator access." }, 403);
      const targetUserId = String(body.user_id ?? "");
      const grant = body.grant === true;
      if (!targetUserId) return response({ error: "Choose a member." }, 400);
      const { data, error } = await admin.rpc("um_set_unit_admin_access", {
        p_actor: user.id, p_target: targetUserId, p_grant: grant, p_reason: String(body.reason ?? ""),
      });
      if (error) throw error;
      return response({ ok: true, data, message: grant ? "Delegated administrator access granted." : "Delegated administrator access revoked." });
    }

    if (action === "seed_demo") {
      if (profile.access_level !== "ano") return response({ error: "Only the ANO may seed demo data." }, 403);
      const { data, error } = await admin.rpc("um_seed_demo");
      if (error) throw error;
      return response({ ok: true, data });
    }

    if (action === "invite") {
      const fullName = String(body.full_name ?? "").trim();
      const regimentalNo = safeRegimental(body.regimental_no);
      const rankTitle = String(body.rank_title ?? "").trim();
      const appointment = String(body.appointment ?? "").trim() || null;
      const isCadet = body.is_cadet !== false;
      const flightId = body.flight_id ? String(body.flight_id) : null;
      if (fullName.length < 2 || rankTitle.length < 2 || rankTitle.length > 100) return response({ error: "Full name and NCC rank are required." }, 400);
      if (flightId) {
        const { data: flight, error } = await admin.from("um_flights").select("id").eq("id", flightId).eq("unit_id", unitId).eq("is_active", true).maybeSingle();
        if (error || !flight) return response({ error: "Selected flight is not active in this unit." }, 400);
      }
      const email = regimentalNo.toLowerCase() + "@unit.local";
      const password = tempPassword();
      const { data: created, error: createError } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
      if (createError || !created.user) throw createError ?? new Error("Could not create account.");
      const userId = created.user.id;
      const { error: profileError } = await admin.from("um_profiles").insert({
        user_id: userId, unit_id: unitId, flight_id: flightId, full_name: fullName, email,
        regimental_no: regimentalNo, rank_title: rankTitle, appointment, access_level: "user",
        force_password_change: true, is_active: true,
      });
      if (profileError) { await admin.auth.admin.deleteUser(userId); throw profileError; }
      const { error: roleError } = await admin.from("um_user_roles").insert({ user_id: userId, unit_id: unitId, role: "cadet", granted_by: user.id });
      if (roleError) { await admin.from("um_profiles").delete().eq("user_id", userId).eq("unit_id", unitId); await admin.auth.admin.deleteUser(userId); throw roleError; }
      if (isCadet) {
        const { error: cadetError } = await admin.from("um_cadets").insert({
          unit_id: unitId, user_id: userId, flight_id: flightId, regimental_no: regimentalNo,
          full_name: fullName, year_of_training: Number(body.year_of_training ?? 1), rank: rankTitle, wing: "AIR",
        });
        if (cadetError) {
          await admin.from("um_user_roles").delete().eq("user_id", userId).eq("unit_id", unitId);
          await admin.from("um_profiles").delete().eq("user_id", userId).eq("unit_id", unitId);
          await admin.auth.admin.deleteUser(userId);
          throw cadetError;
        }
      }
      await admin.from("um_audit_log").insert({
        unit_id: unitId, actor_id: user.id, action: "member_created", table_name: "um_profiles",
        record_id: userId, after_data: { full_name: fullName, regimental_no: regimentalNo, rank_title: rankTitle, appointment, access_level: "user" },
      });
      return response({ ok: true, message: "Member created with standard User access. A temporary password was generated; share it securely.", username: regimentalNo, email, temporary_password: password });
    }

    if (action === "update_member") {
      const targetUserId = String(body.user_id ?? "");
      const isActive = body.is_active === true;
      const flightId = body.flight_id ? String(body.flight_id) : null;
      if (!targetUserId) return response({ error: "Choose an existing member." }, 400);
      if (targetUserId === user.id) return response({ error: "You cannot change your own access from this screen." }, 403);
      const { data: targetProfile, error: targetProfileError } = await admin.from("um_profiles")
        .select("user_id,access_level").eq("user_id", targetUserId).eq("unit_id", unitId).maybeSingle();
      if (targetProfileError || !targetProfile || targetProfile.access_level === "ano" || targetProfile.access_level === "unit_admin") {
        return response({ error: "This member's administrator access cannot be changed through routine member management." }, 403);
      }
      if (flightId) {
        const { data: flight, error } = await admin.from("um_flights").select("id").eq("id", flightId).eq("unit_id", unitId).eq("is_active", true).maybeSingle();
        if (error || !flight) return response({ error: "Selected flight is not active in this unit." }, 400);
      }
      const { error: profileUpdateError } = await admin.from("um_profiles").update({ flight_id: flightId, is_active: isActive }).eq("user_id", targetUserId).eq("unit_id", unitId);
      if (profileUpdateError) throw profileUpdateError;
      const { error: cadetUpdateError } = await admin.from("um_cadets").update({ flight_id: flightId, status: isActive ? "ACTIVE" : "INACTIVE" }).eq("user_id", targetUserId).eq("unit_id", unitId);
      if (cadetUpdateError) throw cadetUpdateError;
      await admin.from("um_audit_log").insert({
        unit_id: unitId, actor_id: user.id, action: "member_updated", table_name: "um_profiles",
        record_id: targetUserId, after_data: { flight_id: flightId, is_active: isActive },
      });
      return response({ ok: true, message: "Member details updated." });
    }

    return response({ error: action === "bootstrap" ? "One-time bootstrap is retired. Register a unit and wait for Platform Super Admin approval." : "Unsupported action." }, 400);
  } catch (error) {
    console.error("unit-manager-admin-users:", error);
    const message = error instanceof Error ? error.message : "Unexpected server error.";
    return response({ error: message }, 400);
  }
});
