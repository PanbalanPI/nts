/**
 * Local-only demo ANO account bootstrap.
 * Refuses any non-local Supabase URL. Never use the demo password on a hosted project.
 * Usage: SUPABASE_URL=http://127.0.0.1:54321 SUPABASE_SERVICE_ROLE_KEY=<local-key> node scripts/seed-local-superadmin.mjs
 */
import { createClient } from "@supabase/supabase-js";

const url = process.env.SUPABASE_URL ?? "";
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";
if (!/^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/i.test(url)) {
  throw new Error("Safety stop: this script only runs against local Supabase at localhost/127.0.0.1.");
}
if (!serviceKey) throw new Error("Set SUPABASE_SERVICE_ROLE_KEY from local Supabase CLI output.");

const supabase = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
const email = "superadmin@example.test";
const password = "12345678";
const { data: listed, error: listError } = await supabase.auth.admin.listUsers({ page: 1, perPage: 1000 });
if (listError) throw listError;
let user = listed.users.find((u) => u.email?.toLowerCase() === email);
if (!user) {
  const { data, error } = await supabase.auth.admin.createUser({
    email, password, email_confirm: true, user_metadata: { full_name: "Local Demo ANO" },
  });
  if (error) throw error;
  user = data.user;
}
if (!user) throw new Error("Unable to create/find local demo user.");
const { data: profile, error: profileError } = await supabase.from("profiles").select("id, role").eq("id", user.id).maybeSingle();
if (profileError) throw profileError;
if (!profile) throw new Error("Auth user exists but no linked profile was created. Check the auth trigger; role was not changed.");
const { error: updateError } = await supabase.from("profiles").update({ role: "ANO", rank_title: "ANO", is_active: true }).eq("id", user.id);
if (updateError) throw updateError;
console.log("Local demo ANO account is ready.");
console.log("Email:    " + email);
console.log("Password: " + password);
console.log("Scope:    local Supabase only; never deploy these credentials.");
