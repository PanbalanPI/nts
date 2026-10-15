"""Notification service.

All automatic notifications are created through `notify()` so the
de-duplication rule ("never create an unread duplicate for the same
recipient/type/title/object") lives in exactly one place.
"""
from django.conf import settings

from .models import Notification


def notify(recipient, *, title, message, ntype=None):
    """Create a notification unless an identical unread one already exists."""
    ntype = ntype or Notification.Type.SYSTEM
    qs = Notification.objects.filter(
        recipient=recipient,
        title=title,
        ntype=ntype,
        read=False,
    )
    if qs.exists():
        return None
    return Notification.objects.create(
        recipient=recipient,
        title=title,
        message=message,
        ntype=ntype,
    )


def notify_roles(roles, *, title, message, ntype=None):
    """Notify every active user holding one of `roles` (list of Role values)."""
    User = settings.AUTH_USER_MODEL
    from django.contrib.auth import get_user_model

    User = get_user_model()
    created = []
    for user in User.objects.filter(role__in=roles, is_active=True):
        n = notify(user, title=title, message=message, ntype=ntype)
        if n is not None:
            created.append(n)
    return created
