"""Shared role/scope helpers and DRF permission classes.

Every viewset must authorise through these helpers so the rules live in one
place. Frontend visibility is convenience only; the backend decides.
"""
from rest_framework.permissions import BasePermission

from apps.accounts.models import Role

COMMAND_ROLES = {Role.ANO, Role.RANKED_SENIOR}
STAFF_ROLES = COMMAND_ROLES | {Role.FLIGHT_SENIOR, Role.SENIOR}


def is_command(user):
    """ANO / Ranked Senior: unit-wide command authority."""
    return user.is_authenticated and user.role in COMMAND_ROLES


def is_staff(user):
    """Any leadership role above Junior."""
    return user.is_authenticated and user.role in STAFF_ROLES


def flight_scope_ok(user, flight_name):
    """True when the user may operate on objects belonging to `flight_name`.

    Command roles see everything; Senior/Flight Senior are limited to their
    own flight; Junior can never operate outside their own profile.
    """
    if not user.is_authenticated:
        return False
    if is_command(user):
        return True
    return bool(user.flight) and user.flight == (flight_name or "")


def cadet_scope_ok(user, cadet):
    """Object-level check: may this user operate on this cadet's records?"""
    if not user.is_authenticated or cadet is None:
        return False
    if is_command(user):
        return True
    if user.role in (Role.SENIOR, Role.FLIGHT_SENIOR):
        return flight_scope_ok(user, cadet.flight)
    # Junior: only their own linked cadet profile.
    return getattr(cadet, "user_id", None) == user.id


def scope_queryset_by_role(qs, user, *, junior_filter, staff_filter):
    """Apply the standard visibility funnel to a queryset.

    junior_filter: callable -> Q/filter kwargs for the user's own objects.
    staff_filter:  callable -> filter for flight-level visibility.
    """
    if user.role == Role.JUNIOR:
        return qs.filter(junior_filter(user))
    if user.role in (Role.SENIOR, Role.FLIGHT_SENIOR):
        return qs.filter(staff_filter(user))
    return qs


class IsAuthenticatedAndStaff(BasePermission):
    """Any leadership role above Junior."""

    def has_permission(self, request, view):
        return is_staff(request.user)


class IsCommand(BasePermission):
    """ANO / Ranked Senior only."""

    def has_permission(self, request, view):
        return is_command(request.user)


class IsAno(BasePermission):
    """ANO only."""

    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.role == Role.ANO
