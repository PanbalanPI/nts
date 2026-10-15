from rest_framework import viewsets
from rest_framework.exceptions import PermissionDenied

from apps.accounts.models import Role
from apps.audit.utils import log_event
from apps.core.permissions import IsCommand, IsAuthenticatedAndStaff, is_command

from .models import Flight
from .serializers import FlightSerializer


class FlightViewSet(viewsets.ModelViewSet):
    """Flight management.

    LIST/RETRIEVE: every authenticated user (visibility is harmless).
    CREATE/UPDATE: ANO + Ranked Senior.
    DELETE:        ANO only.
    """

    queryset = Flight.objects.select_related("flight_senior").all()
    serializer_class = FlightSerializer
    permission_classes = [IsAuthenticatedAndStaff]

    def get_permissions(self):
        if self.action in ("list", "retrieve"):
            from rest_framework.permissions import IsAuthenticated
            return [IsAuthenticated()]
        if self.action == "destroy":
            return [IsCommand()]
        return super().get_permissions()

    def _assert_flight_change_ok(self, serializer):
        """Only the ANO may (re)assign the Flight Senior of a flight."""
        user = self.request.user
        if "flight_senior" in serializer.validated_data and user.role != Role.ANO:
            raise PermissionDenied("Only the ANO can assign Flight Seniors.")

    def perform_create(self, serializer):
        self._assert_flight_change_ok(serializer)
        flight = serializer.save()
        log_event(self.request.user, "FLIGHT_CREATED", flight, {"code": flight.code})

    def perform_update(self, serializer):
        self._assert_flight_change_ok(serializer)
        flight = serializer.save()
        log_event(self.request.user, "FLIGHT_UPDATED", flight, {"code": flight.code})

    def perform_destroy(self, instance):
        log_event(self.request.user, "FLIGHT_DELETED", None, {"code": instance.code})
        instance.delete()
