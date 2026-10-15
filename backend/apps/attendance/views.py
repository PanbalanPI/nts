from django.db.models import Q
from rest_framework import permissions, viewsets
from rest_framework.exceptions import PermissionDenied

from apps.accounts.models import Role
from apps.audit.utils import log_event
from apps.core.permissions import cadet_scope_ok, scope_queryset_by_role

from .models import AttendanceRecord
from .serializers import AttendanceSerializer

MARK_ROLES = {Role.ANO, Role.RANKED_SENIOR, Role.FLIGHT_SENIOR, Role.SENIOR}
EDIT_ROLES = {Role.ANO, Role.RANKED_SENIOR, Role.FLIGHT_SENIOR}


class AttendanceViewSet(viewsets.ModelViewSet):
    queryset = AttendanceRecord.objects.select_related("cadet", "parade", "marked_by").all()
    serializer_class = AttendanceSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        qs = super().get_queryset()
        q = self.request.query_params.get("search", "").strip()
        date = self.request.query_params.get("date", "")
        status_param = self.request.query_params.get("status", "").strip()
        if q:
            qs = qs.filter(Q(cadet__name__icontains=q) | Q(cadet__roll_number__icontains=q))
        if date:
            qs = qs.filter(date=date)
        if status_param:
            qs = qs.filter(status=status_param)
        return scope_queryset_by_role(
            qs,
            self.request.user,
            junior_filter=lambda u: Q(cadet__user=u),
            staff_filter=lambda u: Q(cadet__flight=u.flight) if u.flight else Q(pk__isnull=True),
        )

    def _assert_target_in_scope(self, cadet):
        """Object-level check: the target cadet must be inside the actor's scope."""
        if not cadet_scope_ok(self.request.user, cadet):
            raise PermissionDenied(
                "You can only manage attendance for cadets in your own scope."
            )
        if cadet.status != "ACTIVE":
            raise PermissionDenied("Attendance cannot be recorded for inactive cadets.")

    def perform_create(self, serializer):
        if self.request.user.role not in MARK_ROLES:
            raise PermissionDenied("You cannot mark attendance.")
        cadet = serializer.validated_data["cadet"]
        self._assert_target_in_scope(cadet)
        record = serializer.save(marked_by=self.request.user)
        log_event(
            self.request.user, "ATTENDANCE_MARKED", record,
            {"cadet": cadet.roll_number, "date": str(record.date), "status": record.status},
        )

    def perform_update(self, serializer):
        if self.request.user.role not in EDIT_ROLES:
            raise PermissionDenied("You cannot modify attendance.")
        # Scope is checked against the existing record; if the cadet is being
        # changed, the new target is checked too.
        self._assert_target_in_scope(self.get_object().cadet)
        if "cadet" in serializer.validated_data:
            self._assert_target_in_scope(serializer.validated_data["cadet"])
        record = serializer.save(marked_by=self.request.user)
        log_event(
            self.request.user, "ATTENDANCE_UPDATED", record,
            {"cadet": record.cadet.roll_number, "date": str(record.date), "status": record.status},
        )

    def perform_destroy(self, instance):
        if self.request.user.role not in EDIT_ROLES:
            raise PermissionDenied("You cannot delete attendance records.")
        self._assert_target_in_scope(instance.cadet)
        log_event(
            self.request.user, "ATTENDANCE_DELETED", None,
            {"cadet": instance.cadet.roll_number, "date": str(instance.date), "status": instance.status},
        )
        instance.delete()
