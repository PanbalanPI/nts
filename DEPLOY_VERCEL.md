# Deploying NTS on Vercel

Two Vercel projects from the same repo: one for the frontend, one for the backend.
A PostgreSQL database comes from the Vercel Marketplace (Neon is the usual choice).

## 1. Database
Vercel dashboard → Storage → Create → Neon Postgres (free tier is fine for 70 users).
Copy the **pooled** connection string (it contains `-pooler`). This becomes `DATABASE_URL`.

## 2. Backend project
New Project → import this repo → **Root Directory: `backend`** → Framework: Other.
Environment variables:
| Name | Value |
|---|---|
| `DATABASE_URL` | the Neon pooled connection string |
| `DJANGO_SECRET_KEY` | a new random value (e.g. `python -c "import secrets;print(secrets.token_urlsafe(50))"`) |
| `DJANGO_DEBUG` | `0` |
| `DJANGO_ALLOWED_HOSTS` | your backend domain, e.g. `nts-api.vercel.app` |
| `CORS_ALLOWED_ORIGINS` | your frontend URL, e.g. `https://nts.vercel.app` |
| `CSRF_TRUSTED_ORIGINS` | same as above, with `https://` |

Deploy. Then run the database migrations once from your own computer:
```powershell
cd backend
$env:DATABASE_URL="postgres://...your Neon pooled URL..."
$env:DJANGO_DEBUG="0"
pip install -r requirements.txt
python manage.py migrate
python manage.py createsuperuser
```
(Never run `seed_demo` against the live database.)

## 3. Frontend project
New Project → same repo → **Root Directory: `frontend`** → Framework: Vite.
Environment variable: `VITE_API_URL` = your backend URL, e.g. `https://nts-api.vercel.app`.
Deploy. Then go back to the backend project and set `CORS_ALLOWED_ORIGINS` / `CSRF_TRUSTED_ORIGINS`
to the frontend URL if they weren't set yet, and redeploy the backend.

## Notes
- Vercel functions can't write files, so uploads/media must go to object storage later if you add them.
- The first request after idle can be slow (cold start). Normal for serverless.
- Existing local data (`db.sqlite3`) is not migrated automatically. Export with
  `python manage.py dumpdata` if you need to keep it.
