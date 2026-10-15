from django.db.models import Q
from rest_framework import viewsets
from rest_framework.exceptions import PermissionDenied

from apps.accounts.models import Role
from apps.audit.utils import log_event
from apps.notifications.services import notify
from apps.core.permissions import scope_queryset_by_role

from .models import Certificate
from .serializers import CertificateSerializer

ISSUE_ROLES = {Role.ANO, Role.RANKED_SENIOR}


class CertificateViewSet(viewsets.ModelViewSet):
    queryset = Certificate.objects.select_related("recipient", "issuer").all()
    serializer_class = CertificateSerializer

    def get_queryset(self):
        qs = super().get_queryset()
        recipient_id = self.request.query_params.get("recipient", "").strip()
        if recipient_id:
            qs = qs.filter(recipient_id=recipient_id)
        return scope_queryset_by_role(
            qs,
            self.request.user,
            junior_filter=lambda u: Q(recipient__user=u),
            staff_filter=lambda u: (
                Q(recipient__flight=u.flight) if u.flight else Q(pk__isnull=True)
            ),
        )

    def perform_create(self, serializer):
        if self.request.user.role not in ISSUE_ROLES:
            raise PermissionDenied("Only command staff can issue certificates.")
        certificate = serializer.save(issuer=self.request.user)
        log_event(
            self.request.user, "CERTIFICATE_ISSUED", certificate,
            {"number": certificate.certificate_number, "recipient": certificate.recipient.roll_number},
        )
        if certificate.recipient.user:
            notify(
                certificate.recipient.user,
                title="Certificate issued",
                message=f"You were issued: {certificate.certificate_type} ({certificate.certificate_number}).",
                ntype="CERTIFICATE",
            )

    def perform_update(self, serializer):
        if self.request.user.role not in ISSUE_ROLES:
            raise PermissionDenied("Only command staff can modify certificates.")
        certificate = serializer.save()
        log_event(
            self.request.user, "CERTIFICATE_UPDATED", certificate,
            {"number": certificate.certificate_number, "status": certificate.status},
        )

    def perform_destroy(self, instance):
        # Certificates are legal records: nobody deletes them, they get revoked.
        raise PermissionDenied(
            "Certificates cannot be deleted. Revoke them by setting status to REVOKED."
        )
