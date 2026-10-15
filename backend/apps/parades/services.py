"""Parade workflow service layer.

Every state change goes through these functions. Views must not mutate
Parade.state directly, so the state machine and side-effects stay in one
auditable place.
"""
from django.utils import timezone  # noqa: F401  (kept for future scheduling checks)
from rest_framework.exceptions import PermissionDenied, ValidationError

from apps.accounts.models import Role
from apps.audit.utils import log_event
from apps.notifications.services import notify, notify_roles

from .models import Parade, ParadeState, ParadeType


def submit_for_verification(parade, actor):
    if parade.created_by_id != actor.id and actor.role != Role.ANO:
        raise PermissionDenied("Only the creator or the ANO can submit this parade.")
    if parade.state != ParadeState.DRAFT:
        raise ValidationError("Only a draft parade can be submitted.")

    parade.submit_for_verification(actor)
    log_event(actor, "PARADE_SUBMITTED", parade, {"state": ParadeState.PENDING_VERIFICATION})

    # Route the request to the authority that must decide it.
    required = parade.required_verifier_role()
    notify_roles(
        [required],
        title="Parade awaiting your verification",
        message=f"{parade.title} ({parade.type}) on {parade.date} requires verification.",
        ntype="PARADE",
    )
    return parade


def verify_parade(parade, actor, approved, reason=""):
    """Approve or reject a pending parade (the authority check lives here)."""
    required = parade.required_verifier_role()
    if actor.role != required:
        raise PermissionDenied(
            f"{parade.type.title()} parades require {required.replace('_', ' ').title()} verification."
        )

    try:
        parade = parade.approve(actor, reason) if approved else parade.reject(actor, reason)
    except ValidationError as exc:
        raise ValidationError(str(exc)) from exc

    decision = "approved" if approved else "rejected"
    log_event(
        actor,
        "PARADE_APPROVED" if approved else "PARADE_REJECTED",
        parade,
        {
            "state": parade.state,
            "reason": parade.verification_reason,
        },
    )
    notify(
        parade.created_by,
        title=f"Your parade was {decision}",
        message=(
            f"{parade.title} on {parade.date} was {decision} by {actor.get_full_name() or actor.username}."
            + (f" Reason: {parade.verification_reason}" if parade.verification_reason else "")
        ),
        ntype="PARADE",
    )
    return parade


def cancel_parade(parade, actor):
    if actor.role == Role.JUNIOR:
        raise PermissionDenied("Junior cadets cannot cancel parades.")
    if parade.created_by_id != actor.id and not actor.role in (Role.ANO, Role.RANKED_SENIOR):
        raise PermissionDenied(
            "Only the creator or command staff can cancel this parade."
        )

    try:
        parade = parade.cancel(actor)
    except ValidationError as exc:
        raise ValidationError(str(exc)) from exc

    log_event(actor, "PARADE_CANCELLED", parade, {"state": parade.state})
    return parade


def complete_parade(parade, actor):
    if actor.role not in (Role.ANO, Role.RANKED_SENIOR):
        raise PermissionDenied("Only command staff can mark parades completed.")
    try:
        parade = parade.mark_completed(actor)
    except ValidationError as exc:
        raise ValidationError(str(exc)) from exc

    log_event(actor, "PARADE_COMPLETED", parade, {})
    return parade


def reopen_parade(parade, actor):
    if actor.role not in (Role.ANO, Role.RANKED_SENIOR):
        raise PermissionDenied("Only command staff can resubmit a rejected parade.")
    if parade.created_by_id != actor.id and actor.role != Role.ANO:
        # Ranked Senior may resubmit their own; ANO may resubmit anything.
        raise PermissionDenied(
            "Only the creator or the ANO can resubmit this parade."
        )
    try:
        parade = parade.reopen_as_draft(actor)
    except ValidationError as exc:
        raise ValidationError(str(exc)) from exc

    log_event(actor, "PARADE_REOPENED", parade, {})
    return parade
