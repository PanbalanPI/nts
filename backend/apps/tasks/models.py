from datetime import date

from django.conf import settings
from django.db import models


class Task(models.Model):
    class Status(models.TextChoices):
        TODO = "TODO", "To Do"
        IN_PROGRESS = "IN_PROGRESS", "In Progress"
        COMPLETED = "COMPLETED", "Completed"
        OVERDUE = "OVERDUE", "Overdue"
        CANCELLED = "CANCELLED", "Cancelled"

    class Priority(models.TextChoices):
        LOW = "LOW", "Low"
        MEDIUM = "MEDIUM", "Medium"
        HIGH = "HIGH", "High"

    title = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    assignee = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="assigned_tasks",
    )
    due_date = models.DateField(null=True, blank=True)
    priority = models.CharField(max_length=20, choices=Priority.choices, default=Priority.MEDIUM)
    status = models.CharField(max_length=30, choices=Status.choices, default=Status.TODO)
    completion_date = models.DateField(null=True, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="created_tasks"
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["status", "due_date", "-created_at"]
        indexes = [models.Index(fields=["due_date"]), models.Index(fields=["status"])]

    def __str__(self):
        return self.title

    # ------------------------------------------------------------------
    # Computed overdue state (never stored; see apps/tasks/serializers.py)
    # ------------------------------------------------------------------
    @property
    def is_overdue(self):
        return (
            self.due_date is not None
            and self.due_date < date.today()
            and self.status not in (Task.Status.COMPLETED, Task.Status.CANCELLED)
        )

    @property
    def effective_status(self):
        """Overdue is derived, not stored, so lists/filters stay consistent."""
        if self.is_overdue:
            return Task.Status.OVERDUE
        return self.status
