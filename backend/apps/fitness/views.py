from django.db.models import Q
from rest_framework import permissions, viewsets
from rest_framework.exceptions import PermissionDenied

from apps.accounts.models import Role
from apps.audit.utils import log_event
from apps.core.permissions import cadet_scope_ok, scope_queryset_by_role

from .models import FitnessRecord
from .serializers import FitnessSerializer

RECORD_ROLES = {Role.ANO, Role.RANKED_SENIOR, Role.FLIGHT_SENIOR}


class FitnessViewSet(viewsets.ModelViewSet):
    queryset = FitnessRecord.objects.select_related("cadet", "assessed_by").all()
    serializer_class = FitnessSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        qs = super().get_queryset()
        cadet_id = self.request.query_params.get("cadet", "").strip()
        if cadet_id:
            qs = qs.filter(cadet_id=cadet_id)
        return scope_queryset_by_role(
            qs,
            self.request.user,
            junior_filter=lambda u: Q(cadet__user=u),
            staff_filter=lambda u: Q(cadet__flight=u.flight) if u.flight else Q(pk__isnull=True),
        )

    def _assert_target_in_scope(self, cadet):
        if not cadet_scope_ok(self.request.user, cadet):
            raise PermissionDenied(
                "You can only record fitness for cadets in your own scope."
            )
        if cadet.status != "ACTIVE":
            raise PermissionDenied("Fitness cannot be recorded for inactive cadets.")

    def perform_create(self, serializer):
        if self.request.user.role not in RECORD_ROLES:
            raise PermissionDenied("You cannot record fitness.")
        cadet = serializer.validated_data["cadet"]
        self._assert_target_in_scope(cadet)
        record = serializer.save(assessed_by=self.request.user)
        log_event(
            self.request.user, "FITNESS_RECORDED", record,
            {"cadet": cadet.roll_number, "type": record.assessment_type, "score": str(record.score)},
        )

    def perform_update(self, serializer):
        if self.request.user.role not in RECORD_ROLES:
            raise PermissionDenied("You cannot modify fitness records.")
        self._assert_target_in_scope(self.get_object().cadet)
        if "cadet" in serializer.validated_data:
            self._assert_target_in_scope(serializer.validated_data["cadet"])
        record = serializer.save(assessed_by=self.request.user)
        log_event(
            self.request.user, "FITNESS_UPDATED", record,
            {"cadet": record.cadet.roll_number, "type": record.assessment_type, "score": str(record.score)},
        )

    def perform_destroy(self, instance):
        if self.request.user.role not in RECORD_ROLES:
            raise PermissionDenied("You cannot delete fitness records.")
        self._assert_target_in_scope(instance.cadet)
        log_event(
            self.request.user, "FITNESS_DELETED", None,
            {"cadet": instance.cadet.roll_number, "type": instance.assessment_type},
        )
        instance.delete()
