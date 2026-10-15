from django.db import transaction
from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from apps.accounts.models import Role
from apps.audit.utils import log_event

from .models import Parade, ParadeState, ParadeType
from .serializers import ParadeSerializer
from . import services


class ParadeViewSet(viewsets.ModelViewSet):
    """Parade CRUD + workflow actions.

    Business rules:
      * Everyone authenticated may LIST/RETRIEVE (the queryset is not
        secret; the workflow is what is protected).
      * Junior cadets may never create, modify, delete or verify.
      * Official parades: created by ANO/Ranked Senior, verified by ANO only.
      * Unofficial parades: created by Ranked Senior/Flight Senior (and ANO),
        verified by Ranked Senior only.
      * Edits are allowed while DRAFT/PENDING/REJECTED for the roles that may
        create that parade type; APPROVED/COMPLETED/CANCELLED parades are frozen.
    """

    queryset = Parade.objects.select_related(
        "created_by",
        "verified_by",
    ).all()

    serializer_class = ParadeSerializer
    permission_classes = [IsAuthenticated]

    # Who may create/modify parades of each type.
    CREATOR_ROLES = {
        ParadeType.OFFICIAL: {Role.ANO, Role.RANKED_SENIOR},
        ParadeType.UNOFFICIAL: {Role.ANO, Role.RANKED_SENIOR, Role.FLIGHT_SENIOR},
    }

    EDITABLE_STATES = {
        ParadeState.DRAFT,
        ParadeState.PENDING_VERIFICATION,
        ParadeState.REJECTED,
    }

    # ------------------------------------------------------------------
    # CRUD authorisation
    # ------------------------------------------------------------------
    def get_permissions(self):
        if self.action in ("list", "retrieve"):
            return [IsAuthenticated()]
        return super().get_permissions()

    def _assert_can_manage(self, parade_type, parade=None):
        user = self.request.user
        if user.role == Role.JUNIOR:
            raise PermissionDenied("Junior cadets cannot manage parades.")
        if user.role not in self.CREATOR_ROLES[parade_type]:
            raise PermissionDenied(
                f"{parade_type.title()} parades are managed by "
                f"{', '.join(r.replace('_', ' ').title() for r in sorted(self.CREATOR_ROLES[parade_type]))}."
            )
        if parade is not None:
            # Only command staff may edit someone else's parade.
            if parade.created_by_id != user.id and user.role not in (Role.ANO, Role.RANKED_SENIOR):
                raise PermissionDenied(
                    "Only the creator or command staff can modify this parade."
                )

    def perform_create(self, serializer):
        parade_type = serializer.validated_data["type"]
        self._assert_can_manage(parade_type)
        parade = serializer.save(created_by=self.request.user)
        log_event(
            self.request.user,
            "PARADE_CREATED",
            parade,
            {"type": parade.type, "date": str(parade.date)},
        )

    def perform_update(self, serializer):
        parade = self.get_object()
        self._assert_can_manage(parade.type, parade)
        if parade.state not in self.EDITABLE_STATES:
            raise PermissionDenied(
                "A decided parade can no longer be edited. Cancel it or resubmit instead."
            )
        if "state" in serializer.validated_data or "verification_status" in serializer.validated_data:
            raise PermissionDenied(
                "Parade state changes must go through the workflow actions."
            )
        old_state = parade.state
        parade = serializer.save()
        if parade.state != old_state:
            log_event(self.request.user, "PARADE_UPDATED", parade, {"state": parade.state})
        else:
            log_event(self.request.user, "PARADE_UPDATED", parade, {})

    def perform_destroy(self, instance):
        user = self.request.user
        if user.role != Role.ANO:
            raise PermissionDenied("Only the ANO can delete parades.")
        log_event(user, "PARADE_DELETED", None, {"title": instance.title, "date": str(instance.date)})
        instance.delete()

    # ------------------------------------------------------------------
    # Workflow actions
    # ------------------------------------------------------------------
    @action(detail=True, methods=["post"])
    def verify(self, request, pk=None):
        """Approve or reject a pending parade (authority enforced in service)."""
        parade = self.get_object()
        approved = bool(request.data.get("approved", False))
        reason = request.data.get("reason", "")

        try:
            updated = services.verify_parade(parade, request.user, approved, reason)
        except ValidationError as exc:
            raise ValidationError(exc.message_dict if hasattr(exc, "message_dict") else exc.messages)
        return Response(self.get_serializer(updated).data)

    @action(detail=True, methods=["post"])
    def submit(self, request, pk=None):
        parade = self.get_object()
        updated = services.submit_for_verification(parade, request.user)
        return Response(self.get_serializer(updated).data)

    @action(detail=True, methods=["post"])
    def cancel(self, request, pk=None):
        parade = self.get_object()
        updated = services.cancel_parade(parade, request.user)
        return Response(self.get_serializer(updated).data)

    @action(detail=True, methods=["post"])
    def complete(self, request, pk=None):
        parade = self.get_object()
        updated = services.complete_parade(parade, request.user)
        return Response(self.get_serializer(updated).data)

    @action(detail=True, methods=["post"])
    def reopen(self, request, pk=None):
        parade = self.get_object()
        updated = services.reopen_parade(parade, request.user)
        return Response(self.get_serializer(updated).data)
