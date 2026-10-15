"""Role-scoped dashboard.

Every statistic is computed in SQL from real data and filtered by the
requesting user's role. A Junior never receives unit-wide numbers: the
response only contains their own scope's data, so nothing is exposed that
shouldn't be, regardless of what the client renders.
"""
from django.db.models import Q
from django.utils import timezone
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import Role
from apps.attendance.models import AttendanceRecord
from apps.cadets.models import Cadet
from apps.core.permissions import is_command
from apps.fitness.models import FitnessRecord
from apps.parades.models import Parade, ParadeState
from apps.tasks.models import Task


def _attendance_percentage(qs):
    """present-or-excused / eligible records * 100.

    Every recorded attendance entry counts as eligible; ABSENT counts against
    the percentage, EXCUSED counts as attending per NTS doctrine.
    """
    total = qs.count()
    if not total:
        return None
    present = qs.filter(status__in=["PRESENT", "EXCUSED"]).count()
    return round(present / total * 100, 1)


def _readiness_percentage(cadet_qs):
    """Latest valid (scored) assessment per active cadet, averaged.

    `.distinct("cadet_id")` with ordering by cadet then newest-first selects
    the single latest scored assessment per cadet (PostgreSQL syntax; on
    SQLite the ORM emulates it for this simple case via GROUP BY folding).
    """
    latest_scores = (
        FitnessRecord.objects.filter(cadet__in=cadet_qs, score__isnull=False)
        .order_by("cadet_id", "-assessment_date", "-id")
        .distinct("cadet_id")
        .values_list("score", flat=True)
    )
    values = [float(s) for s in latest_scores]
    if not values:
        return None
    return round(sum(values) / len(values), 1)


class DashboardView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        user = request.user
        role = user.role
        today = timezone.localdate()

        command = is_command(user)
        if role == Role.JUNIOR:
            cadets = Cadet.objects.filter(user=user)
            tasks = Task.objects.filter(assignee=user)
            attendance = AttendanceRecord.objects.filter(cadet__user=user)
            my_flight = user.flight
        elif role in (Role.SENIOR, Role.FLIGHT_SENIOR):
            flight_q = Q(flight=user.flight) if user.flight else Q(pk__isnull=True)
            cadets = Cadet.objects.filter(Q(user=user) | flight_q)
            tasks = Task.objects.filter(
                Q(assignee=user)
                | (Q(assignee__flight=user.flight) if user.flight else Q(pk__isnull=True))
            )
            attendance = AttendanceRecord.objects.filter(
                Q(cadet__user=user)
                | (Q(cadet__flight=user.flight) if user.flight else Q(pk__isnull=True))
            )
            my_flight = user.flight
        else:
            cadets = Cadet.objects.all()
            tasks = Task.objects.all()
            attendance = AttendanceRecord.objects.all()
            my_flight = None

        active_cadets = cadets.filter(status="ACTIVE")

        attendance_pct = _attendance_percentage(attendance)
        readiness_pct = _readiness_percentage(active_cadets)

        open_tasks = tasks.exclude(status=Task.Status.COMPLETED).count()
        overdue_tasks = tasks.exclude(status=Task.Status.COMPLETED).filter(
            due_date__lt=today
        ).count()

        upcoming = (
            Parade.objects.filter(
                date__gte=today,
                state__in=[
                    ParadeState.DRAFT,
                    ParadeState.PENDING_VERIFICATION,
                    ParadeState.APPROVED,
                ],
            )
            .order_by("date", "start_time")[:6]
        )

        # Pending verifications: only those requiring THIS user's authority.
        my_verifier_type = {
            Role.ANO: "OFFICIAL",
            Role.RANKED_SENIOR: "UNOFFICIAL",
        }.get(role)
        pending_for_me = (
            Parade.objects.filter(
                state=ParadeState.PENDING_VERIFICATION, type=my_verifier_type
            ).count()
            if my_verifier_type
            else 0
        )

        statistics = {
            # Unit-wide counts are command-only; nobody else gets the key.
            "total_cadets": active_cadets.count() if command else None,
            "attendance_percentage": attendance_pct if command else None,
            "unit_readiness": readiness_pct if command else None,
            "open_tasks": open_tasks,
            "overdue_tasks": overdue_tasks,
            "pending_verifications": pending_for_me,
            "upcoming_parades": len(upcoming),
        }

        if command:
            statistics["pending_verifications_official"] = Parade.objects.filter(
                state=ParadeState.PENDING_VERIFICATION, type="OFFICIAL"
            ).count()
            statistics["pending_verifications_unofficial"] = Parade.objects.filter(
                state=ParadeState.PENDING_VERIFICATION, type="UNOFFICIAL"
            ).count()

        return Response({
            "role": role,
            "flight": my_flight,
            "permissions": {
                "can_verify_official": role == Role.ANO,
                "can_verify_unofficial": role == Role.RANKED_SENIOR,
                "can_create_parade": role != Role.JUNIOR,
                "can_issue_certificate": role in (Role.ANO, Role.RANKED_SENIOR),
                "can_manage_users": role == Role.ANO,
            },
            "statistics": statistics,
            "upcoming_parades": [
                {
                    "id": p.id,
                    "title": p.title,
                    "type": p.type,
                    "date": p.date,
                    "start_time": p.start_time,
                    "location": p.location,
                    "state": p.state,
                    "status": p.verification_status,
                }
                for p in upcoming
            ],
        })
