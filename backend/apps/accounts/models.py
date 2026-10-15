from django.contrib.auth.models import AbstractUser
from django.db import models


class Role(models.TextChoices):
    ANO = "ANO", "ANO"
    RANKED_SENIOR = "RANKED_SENIOR", "Ranked Senior"
    FLIGHT_SENIOR = "FLIGHT_SENIOR", "Flight Senior"
    SENIOR = "SENIOR", "Senior"
    JUNIOR = "JUNIOR", "Junior"


class User(AbstractUser):
    role = models.CharField(
        max_length=30,
        choices=Role.choices,
        default=Role.JUNIOR,
    )

    roll_number = models.CharField(
        max_length=50,
        unique=True,
        null=True,
        blank=True,
    )

    flight = models.CharField(
        max_length=100,
        blank=True,
    )

    rank_title = models.CharField(
        max_length=100,
        blank=True,
    )

    @property
    def role_level(self):
        levels = {
            Role.ANO: 5,
            Role.RANKED_SENIOR: 4,
            Role.FLIGHT_SENIOR: 3,
            Role.SENIOR: 2,
            Role.JUNIOR: 1,
        }
        return levels[self.role]

    def is_at_least(self, role):
        return self.role_level >= {
            Role.ANO: 5,
            Role.RANKED_SENIOR: 4,
            Role.FLIGHT_SENIOR: 3,
            Role.SENIOR: 2,
            Role.JUNIOR: 1,
        }[role]