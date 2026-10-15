# NTS Frontend to Backend Handoff

This document lists requirements, missing endpoints, and contract expectations discovered during the frontend implementation. If the backend is being worked on concurrently, please ensure these are addressed.

## 1. Audit Log Endpoint
**Issue:** The `apps.audit.urls` exists but is not included in `backend/config/urls.py`.
**Requirement:** The frontend expects the audit log to be accessible at `/api/audit/` for users with Command roles (ANO, RANKED_SENIOR).
**Action:** In `backend/config/urls.py`, add:
```python
path("api/audit/", include("apps.audit.urls")),
```
Ensure the viewset returns a list of audit logs with fields: `timestamp`, `actor_name` (or `actor`), `action`, `object_type`, `object_id`.

## 2. Parades Verification Payload
**Issue:** The Parade Verification UI sends a POST request to `/api/parades/{id}/verify/`.
**Requirement:** The backend should accept the following payload:
```json
{
  "decision": "APPROVED", // or "REJECTED"
  "reason": "Optional reason, but required if decision is REJECTED"
}
```
**Action:** Ensure the `verify` action in `ParadeViewSet` handles this correctly and applies the state machine logic (e.g. changing status to `APPROVED` or `REJECTED`, logging the verifier, and setting the reason).

## 3. Dashboard Data Payload
**Issue:** The frontend expects aggregated metrics from `/api/dashboard/`.
**Requirement:** The JSON payload should match:
```json
{
  "total_cadets": 120,
  "attendance_rate": 92.5,
  "readiness_rate": 88.0,
  "open_tasks": 5,
  "overdue_tasks": 2,
  "upcoming_parades": [
    { "id": 1, "title": "Weekly Drill", "date": "2026-10-10", "type": "OFFICIAL", "status": "APPROVED" }
  ],
  "pending_verifications": 1
}
```
**Action:** Ensure `apps.dashboard.views` returns this structure correctly based on the user's role.

## 4. User Management Endpoint
**Issue:** Frontend expects `/api/auth/users/`.
**Requirement:** The ANO role needs a way to view all users, activate/deactivate them, and change their roles.
**Action:** Ensure `UserViewSet` allows CRUD operations for ANOs and properly validates role escalations.

## 5. Security & Permissions
**Constraint:** Frontend handles UI visibility only. Do NOT rely on the frontend to hide buttons as a security measure. The backend MUST enforce all object-level and role-level permissions as requested in the original task.
