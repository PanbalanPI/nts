# NCC Unit Manager

Mobile-first NCC unit ERP for parade scheduling, attendance, leave, kit inventory, fitness assessments, certificate syllabus progress, exam records, certificates, notifications and audit history.

## Architecture

- **Frontend:** React + Vite, responsive CSS design system, installable PWA shell.
- **Backend:** Supabase Auth + PostgreSQL + RLS + transactional PostgreSQL RPCs + Supabase Edge Function for provisioning.
- **Security:** separate `um_user_roles` table; unit-scoped row-level policies; cross-unit composite foreign keys; protected parade transitions; transactional attendance, inventory issue/return, leave review and certificate eligibility operations.
- The legacy Django backend and legacy NTS schema are retained for compatibility; the new Unit Manager frontend talks directly to Supabase and uses the `um_` schema. It does not silently mix the older ANO/Junior role model into the new `admin/officer/senior/cadet` model.

## Local development

1. Install Node.js 22 or newer.
2. `cd frontend`
3. `npm install`
4. Copy `.env.example` to `.env.local` and set `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`.
5. `npm run dev`

Build validation: `npm run build`.

Never expose a Supabase service-role key in a `VITE_*` variable or frontend file.

## First-time unit setup

Deploy `supabase/functions/unit-manager-admin-users/index.ts` as the `unit-manager-admin-users` Edge Function. The function is deployed with JWT verification disabled only because the one-time bootstrap must run before an admin exists; every non-bootstrap action validates the caller's Supabase JWT and admin role itself.

In Supabase Dashboard → Edge Functions → Secrets, set:
- `UNIT_MANAGER_BOOTSTRAP_SECRET`: a new random secret of at least 20 characters. Keep it private and do not commit it.
- `UNIT_MANAGER_ALLOWED_ORIGIN`: your deployed frontend origin, for example `https://nts-dusky.vercel.app`.

Open the app and choose **First-time unit setup**. Enter the configured bootstrap secret, unit name/code, administrator email, full name and a strong initial password (12+ characters). Bootstrap is locked once the first role assignment exists. After that, admins provision officers/seniors by email invitation and cadets by regimental number. Cadets receive a generated temporary password once and must change it at first login.

## Demo data

After signing in as the unit admin, open **User management → Seed demo data**. It adds clearly fictional cadets, flights, historical parades and attendance, fitness records, inventory issues, a leave request, syllabus topics and a camp. Do not seed demo data into a unit containing real operational records.

## Database migrations

Migrations are under `supabase/migrations/`. The database migrations for this branch have been applied to the connected Supabase project. Keep the SQL migration files in source control as the schema's source of truth.

## Deployment

Configure the Vercel frontend root directory as `frontend`. Set the two browser-safe Supabase environment variables there. Configure the Edge Function secrets above in Supabase, not in Vercel's public `VITE_*` variables. The service-role key remains in Supabase's server-side environment only.

## Scope notes

This build deliberately excludes QR check-in, offline data sync, SMS/WhatsApp, and HQ multi-unit dashboards. The PWA caches only the static shell; authenticated API data is never cached by the service worker.
