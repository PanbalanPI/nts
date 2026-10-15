# NTS — NCC Training & Tracking System

Clean starter for the NCC Air Wing application.

Stack:
- React + TypeScript + Vite
- Django + Django REST Framework
- PostgreSQL
- Vercel for the frontend

Role hierarchy:
ANO > Ranked Senior > Flight Senior > Senior > Junior

Verification:
- Official parade -> ANO
- Unofficial parade -> Ranked Senior

## Backend
```powershell
cd backend
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
python manage.py migrate
python manage.py createsuperuser
python manage.py runserver
```

## Frontend
Open a second terminal:
```powershell
cd frontend
npm install
npm run dev
```
