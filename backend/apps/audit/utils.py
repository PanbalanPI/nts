"""Append-only audit trail helpers.

Audit records are created here and nowhere else. Records are never modified
or deleted through the API; the Django admin exposes them read-only.
"""
from .models import AuditLog


def log_event(actor, action, obj=None, metadata=None):
    """Record one audit event.

    actor     -- the user performing the action (None for system events)
    action    -- short verb phrase, e.g. "PARADE_APPROVED"
    obj       -- the model instance acted upon (optional)
    metadata  -- dict of structured, JSON-serialisable context
    """
    return AuditLog.objects.create(
        actor=actor,
        action=action,
        object_type=obj.__class__.__name__ if obj else "",
        object_id=str(getattr(obj, "pk", "") or ""),
        metadata=metadata or {},
    )
