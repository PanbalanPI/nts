from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models, transaction
from django.utils import timezone

from apps.accounts.models import Role


class ParadeType(models.TextChoices):
    OFFICIAL = "OFFICIAL", "Official"
    UNOFFICIAL = "UNOFFICIAL", "Unofficial"


class ParadeState(models.TextChoices):
    """Explicit lifecycle states for every parade."""

    DRAFT = "DRAFT", "Draft"
    PENDING_VERIFICATION = "PENDING_VERIFICATION", "Pending verification"
    APPROVED = "APPROVED", "Approved"
    REJECTED = "REJECTED", "Rejected"
    CANCELLED = "CANCELLED", "Cancelled"
    COMPLETED = "COMPLETED", "Completed"


class VerificationStatus(models.TextChoices):
    """Compatibility alias for the pre-existing public field name."""

    PENDING = "PENDING", "Pending"
    VERIFIED = "VERIFIED", "Verified"
    REJECTED = "REJECTED", "Rejected"


STATE_TO_VERIFICATION_STATUS = {
    ParadeState.PENDING_VERIFICATION: VerificationStatus.PENDING,
    ParadeState.APPROVED: VerificationStatus.VERIFIED,
    ParadeState.REJECTED: VerificationStatus.REJECTED,
    ParadeState.COMPLETED: VerificationStatus.VERIFIED,
    ParadeState.CANCELLED: VerificationStatus.REJECTED,
}

# Allowed transitions of the state machine.
VALID_TRANSITIONS = {
    ParadeState.DRAFT: {
        ParadeState.PENDING_VERIFICATION,
        ParadeState.CANCELLED,
    },
    ParadeState.PENDING_VERIFICATION: {
        ParadeState.APPROVED,
        ParadeState.REJECTED,
        ParadeState.CANCELLED,
    },
    ParadeState.APPROVED: {
        ParadeState.COMPLETED,
        ParadeState.CANCELLED,
    },
    ParadeState.REJECTED: {
        ParadeState.DRAFT,  # resubmission path: clear the decision, re-enter flow
        ParadeState.CANCELLED,
    },
    ParadeState.COMPLETED: set(),  # terminal
    ParadeState.CANCELLED: set(),  # terminal
}


class Parade(models.Model):
    title = models.CharField(max_length=200)

    type = models.CharField(
        max_length=20,
        choices=ParadeType.choices,
    )

    date = models.DateField()
    start_time = models.TimeField()
    end_time = models.TimeField()

    location = models.CharField(max_length=255)
    description = models.TextField(blank=True)

    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="created_parades",
    )

    # Canonical lifecycle state.
    state = models.CharField(
        max_length=30,
        choices=ParadeState.choices,
        default=ParadeState.DRAFT,
    )

    # Legacy verification flag kept in lockstep with `state` for existing
    # consumers (serializer, dashboard, admin, tests).
    verification_status = models.CharField(
        max_length=20,
        choices=VerificationStatus.choices,
        default=VerificationStatus.PENDING,
    )

    verified_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="verified_parades",
    )

    verification_reason = models.TextField(blank=True)

    verified_at = models.DateTimeField(
        null=True,
        blank=True,
    )

    cancelled_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-date", "-start_time"]
        indexes = [
            models.Index(fields=["date"]),
            models.Index(fields=["state"]),
            models.Index(fields=["type"]),
        ]

    # ------------------------------------------------------------------
    # State machine helpers
    # ------------------------------------------------------------------
    def _sync_status(self):
        """Keep the legacy `verification_status` field aligned with state."""
        self.verification_status = STATE_TO_VERIFICATION_STATUS.get(
            self.state, VerificationStatus.PENDING
        )

    def can_transition_to(self, new_state):
        return new_state in VALID_TRANSITIONS.get(self.state, set())

    def clean(self):
        super().clean()

        if self.start_time and self.end_time and self.end_time <= self.start_time:
            raise ValidationError("End time must be after start time.")

        # Locked decision fields after a decision has been recorded.
        decided = self.verified_by is not None or self.verified_at is not None
        if self.state == ParadeState.PENDING_VERIFICATION and decided:
            raise ValidationError(
                "A pending parade cannot already have a verifier recorded."
            )

        if self.state in (ParadeState.APPROVED, ParadeState.REJECTED):
            if self.verified_by is None or self.verified_at is None:
                raise ValidationError(
                    "An approved/rejected parade must record verifier and time."
                )

        if self.state == ParadeState.COMPLETED and self.completed_at is None:
            raise ValidationError(
                "A completed parade must record its completion timestamp."
            )

        if self.state == ParadeState.CANCELLED and self.cancelled_at is None:
            raise ValidationError(
                "A cancelled parade must record its cancellation timestamp."
            )

    # ------------------------------------------------------------------
    # Role rules
    # ------------------------------------------------------------------
    def required_verifier_role(self):
        if self.type == ParadeType.OFFICIAL:
            return Role.ANO
        if self.type == ParadeType.UNOFFICIAL:
            return Role.RANKED_SENIOR
        return None

    def can_be_verified_by(self, user):
        if not user or not user.is_authenticated:
            return False
        if self.state != ParadeState.PENDING_VERIFICATION:
            return False
        return user.role == self.required_verifier_role()

    # ------------------------------------------------------------------
    # Transitions (all atomic; caller decides where they happen in code)
    # ------------------------------------------------------------------
    @transaction.atomic
    def submit_for_verification(self, actor):
        if self.state != ParadeState.DRAFT:
            raise ValidationError("Only a draft parade can be submitted.")
        self.state = ParadeState.PENDING_VERIFICATION
        self._sync_status()
        self.full_clean(exclude=None)
        self.save()
        return self

    @transaction.atomic
    def _decide(self, actor, approved, reason=""):
        """Shared implementation of approve/reject.

        Re-reads the row under select_for_update so two concurrent
        verifications cannot both pass the pending-state check.
        """
        fresh = type(self).objects.select_for_update().get(pk=self.pk)
        if fresh.state != ParadeState.PENDING_VERIFICATION:
            raise ValidationError(
                "This parade is not awaiting verification."
            )
        required = self.required_verifier_role()
        if actor.role != required:
            raise ValidationError("You are not the designated verifier for this parade.")
        if not approved:
            if not (reason or "").strip():
                raise ValidationError("A rejection reason is required.")

        now = timezone.now()
        self.state = (
            ParadeState.APPROVED if approved else ParadeState.REJECTED
        )
        self.verified_by = actor
        self.verification_reason = (reason or "").strip()
        self.verified_at = now
        self._sync_status()
        self.full_clean()
        self.save()
        return self

    def approve(self, actor, reason=""):
        return self._decide(actor, True, reason)

    def reject(self, actor, reason):
        return self._decide(actor, False, reason)

    @transaction.atomic
    def cancel(self, actor):
        instance = type(self).objects.select_for_update().get(pk=self.pk)
        if not instance.can_transition_to(ParadeState.CANCELLED):
            raise ValidationError(
                f"Cannot cancel a parade in state {instance.state}."
            )
        instance.state = ParadeState.CANCELLED
        instance.cancelled_at = timezone.now()
        if not instance.verified_by:
            # Cancelled without a decision: keep verifier fields empty.
            instance.verification_status = VerificationStatus.REJECTED
        instance._sync_status()
        instance.full_clean()
        instance.save()
        return instance

    @transaction.atomic
    def mark_completed(self, actor):
        instance = type(self).objects.select_for_update().get(pk=self.pk)
        if not instance.can_transition_to(ParadeState.COMPLETED):
            raise ValidationError(
                f"Cannot complete a parade in state {instance.state}."
            )
        instance.state = ParadeState.COMPLETED
        instance.completed_at = timezone.now()
        instance._sync_status()
        instance.full_clean()
        instance.save()
        return instance

    @transaction.atomic
    def reopen_as_draft(self, actor):
        """Rejected -> DRAFT, clearing the decision so it can be resubmitted."""
        instance = type(self).objects.select_for_update().get(pk=self.pk)
        if instance.state != ParadeState.REJECTED:
            raise ValidationError("Only a rejected parade can be resubmitted.")
        instance.state = ParadeState.DRAFT
        instance.verified_by = None
        instance.verification_reason = ""
        instance.verified_at = None
        instance.verification_status = VerificationStatus.PENDING
        instance._sync_status()
        instance.full_clean()
        instance.save()
        return instance

    def __str__(self):
        return f"{self.title} ({self.date}) [{self.state}]"
