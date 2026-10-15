from rest_framework import serializers

from .models import AuditLog


class AuditLogSerializer(serializers.ModelSerializer):
    actor_name = serializers.CharField(
        source="actor.get_full_name", read_only=True, default=""
    )
    actor_role = serializers.CharField(
        source="actor.role", read_only=True, default=""
    )

    class Meta:
        model = AuditLog
        fields = [
            "id", "timestamp", "actor", "actor_name", "actor_role",
            "action", "object_type", "object_id", "metadata",
        ]
