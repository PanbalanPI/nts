# NTS Air Wing Command — Frontend

React + Vite frontend connected to Supabase Auth and the NTS PostgreSQL schema.

## Local development

1. Install Node.js 20.19+ (or a compatible current LTS) and npm.
2. From this directory, install dependencies:
   ```sh
   npm install
   ```
3. Copy `.env.example` to `.env.local` and set `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`.
4. Run `npm run dev` and open the local URL Vite prints.

## Vercel

Set the project root to `frontend`, framework preset to Vite, build command to `npm run build`, and output directory to `dist`. Add the two Vite variables to Preview and Production.

## First ANO bootstrap (one-time, trusted administrator only)

1. In Supabase Dashboard → Authentication → Users, invite the official ANO email address. Do not share or hardcode a password.
2. After the user is created, open SQL Editor and replace the email below with the exact invited email. Run this as the trusted database owner:

   ```sql
   update public.profiles p
   set role = 'ANO'::public.command_role,
       rank_title = 'ANO',
       is_active = true
   from auth.users u
   where p.id = u.id
     and lower(u.email) = lower('ano@example.org');
   ```

3. Confirm exactly one intended account was updated. The ANO signs in and the **ANO Administration** navigation item appears.
4. If no profile row exists, stop and investigate the `on_auth_user_created` trigger instead of creating an unrelated profile ID.

The migration `supabase/migrations/20261019_prevent_ano_role_escalation.sql` prevents ordinary authenticated sessions from granting themselves or another user the ANO role. Use a trusted database-owner session for the initial bootstrap. Do not use a service-role key in the browser.

## ANO Administration

- Invite unit members by email into Ranked Senior, Flight Senior, Senior, or Junior roles.
- Update names, service numbers, rank titles, roles, flight assignments, and active/inactive status.
- Create and edit flights, assign Flight Seniors, and deactivate flights without breaking historical references.
- Record administrative changes in the audit trail where supported by database policies.

Invitations are handled by the JWT-protected Supabase Edge Function `ano-admin-users`. It validates the caller's JWT and rechecks that the caller has an active ANO profile before using server-side credentials. The function never returns its service-role key. Additional ANO accounts are deliberately excluded from ordinary invitations.

## Security and limitations

- No public self-signup or shared default passwords.
- Browser code uses only the publishable key.
- Row Level Security and server-side authorization—not navigation visibility—must protect every operation.
- Historical/audit records are preserved; user and flight access should be deactivated rather than hard-deleted.
- Parade/report verification controls are not exposed until the corresponding server-side workflow has been validated.
- Run build and end-to-end tests before operational use.
