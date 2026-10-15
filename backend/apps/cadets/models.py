from django.conf import settings
from django.db import models


class Cadet(models.Model):
    class Status(models.TextChoices):
        ACTIVE = "ACTIVE", "Active"
        INACTIVE = "INACTIVE", "Inactive"

    class CadetRole(models.TextChoices):
        RANKED_SENIOR = "RANKED_SENIOR", "Ranked Senior"
        FLIGHT_SENIOR = "FLIGHT_SENIOR", "Flight Senior"
        SENIOR = "SENIOR", "Senior"
        JUNIOR = "JUNIOR", "Junior"

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="cadet_profile",
        null=True,
        blank=True,
    )
    name = models.CharField(max_length=150)
    roll_number = models.CharField(max_length=50, unique=True)
    rank = models.CharField(max_length=100, blank=True)
    role = models.CharField(
        max_length=30,
        choices=CadetRole.choices,
        default=CadetRole.JUNIOR,
    )
    flight = models.CharField(max_length=100, blank=True)
    phone = models.CharField(max_length=20, blank=True)
    email = models.EmailField(blank=True)
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.ACTIVE,
    )
    joined_date = models.DateField(null=True, blank=True)
    notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["name"]
        indexes = [
            models.Index(fields=["roll_number"]),
            models.Index(fields=["flight"]),
            models.Index(fields=["status"]),
        ]

    def __str__(self):
        return f"{self.name} ({self.roll_number})"