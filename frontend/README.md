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

## Build and lint

```sh
npm run build
npm run lint
npm run preview
```

## Vercel

Set the project root directory to `frontend`, framework preset to Vite, build command to `npm run build`, and output directory to `dist`. Add the two Vite environment variables for Preview and Production, then redeploy.

## Authentication and security

- The app uses Supabase Auth password sign-in; self-service sign-up is intentionally not provided.
- Each authenticated user must have an active `public.profiles` row whose ID matches `auth.users.id`.
- Browser code uses only the publishable key. Never use a service-role or secret key in a Vite variable.
- Row Level Security must authorize every select/insert/update/delete. UI navigation is not a security boundary.
- Parade/report verification controls are intentionally omitted until the corresponding database policies or audited server-side RPCs are verified. The application must not grant approval authority based only on a frontend role check.
- Demo records are not fabricated. Empty database states are displayed until real data is entered.

## Modules

Dashboard, cadet directory, flights, parades, activities, reports, attendance, tasks, fitness assessments, certificates, notifications, and audit trail. Dashboard counts are fetched from the database. Operational create forms insert draft/planned records and rely on RLS for authorization.

## Current limitations

This is the frontend integration layer, not a claim that all backend workflows have been validated. The deployed Supabase schema, role-specific RLS policies, verification rules, storage policies, seed data, and end-to-end tests must be checked before operational use. Do not use this application for official unit records until that verification is complete.
