from django.db.models import Q
from rest_framework import filters, permissions, viewsets

from apps.accounts.models import Role
from apps.core.permissions import is_command

from .models import AuditLog
from .serializers import AuditLogSerializer


class AuditLogViewSet(viewsets.ReadOnlyModelViewSet):
    """Append-only audit trail. Visible to command staff (ANO / Ranked Senior) only."""

    queryset = AuditLog.objects.select_related("actor").all()
    serializer_class = AuditLogSerializer
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [filters.SearchFilter, filters.OrderingFilter]
    search_fields = ["action", "object_type", "object_id", "actor__username"]
    ordering_fields = ["timestamp"]
    ordering = ["-timestamp"]

    def get_queryset(self):
        qs = super().get_queryset()
        params = self.request.query_params
        action_param = params.get("action", "").strip()
        object_type = params.get("object_type", "").strip()
        actor = params.get("actor", "").strip()
        if action_param:
            qs = qs.filter(action=action_param)
        if object_type:
            qs = qs.filter(object_type=object_type)
        if actor:
            qs = qs.filter(actor__username__iexact=actor)
        return qs
