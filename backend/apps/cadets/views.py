from django.db.models import Q
from rest_framework import permissions, viewsets
from rest_framework.exceptions import PermissionDenied

from apps.accounts.models import Role
from apps.audit.utils import log_event
from apps.core.permissions import scope_queryset_by_role

from .models import Cadet
from .serializers import CadetSerializer

MANAGE_ROLES = {Role.ANO, Role.RANKED_SENIOR, Role.FLIGHT_SENIOR}
DELETE_ROLES = {Role.ANO, Role.RANKED_SENIOR}


class CadetViewSet(viewsets.ModelViewSet):
    queryset = Cadet.objects.select_related("user").prefetch_related(
        "attendance_records", "fitness_records", "certificates"
    ).all()
    serializer_class = CadetSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        qs = super().get_queryset()
        params = self.request.query_params
        q = params.get("search", "").strip()
        flight = params.get("flight", "").strip()
        status = params.get("status", "").strip()
        role = params.get("role", "").strip()
        if q:
            qs = qs.filter(Q(name__icontains=q) | Q(roll_number__icontains=q) | Q(rank__icontains=q))
        if flight:
            qs = qs.filter(flight__iexact=flight)
        if status:
            qs = qs.filter(status=status)
        if role:
            qs = qs.filter(role=role)
        return scope_queryset_by_role(
            qs,
            self.request.user,
            junior_filter=lambda u: Q(user=u),
            staff_filter=lambda u: Q(user=u) | Q(flight=u.flight) if u.flight else Q(user=u),
        )

    def _assert_manage_scope(self, cadet):
        """Object-level guard: Flight Senior restricted to their own flight."""
        user = self.request.user
        if user.role == Role.FLIGHT_SENIOR and cadet.flight != user.flight:
            raise PermissionDenied("Flight Seniors can only manage their own flight's cadets.")

    def perform_create(self, serializer):
        if self.request.user.role not in MANAGE_ROLES:
            raise PermissionDenied("You do not have permission to create cadets.")
        cadet = serializer.save()
        log_event(self.request.user, "CADET_CREATED", cadet, {"roll_number": cadet.roll_number})

    def perform_update(self, serializer):
        if self.request.user.role not in MANAGE_ROLES:
            raise PermissionDenied("You do not have permission to modify cadets.")
        cadet = self.get_object()
        self._assert_manage_scope(cadet)
        role_before = cadet.role
        cadet = serializer.save()
        if cadet.role != role_before:
            log_event(
                self.request.user, "CADET_ROLE_CHANGED", cadet,
                {"roll_number": cadet.roll_number, "from": role_before, "to": cadet.role},
            )
        else:
            log_event(self.request.user, "CADET_UPDATED", cadet, {"roll_number": cadet.roll_number})

    def perform_destroy(self, instance):
        if self.request.user.role not in DELETE_ROLES:
            raise PermissionDenied("You do not have permission to delete cadets.")
        self._assert_manage_scope(instance)
        log_event(self.request.user, "CADET_DELETED", None, {"roll_number": instance.roll_number})
        instance.delete()
