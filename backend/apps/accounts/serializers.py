from rest_framework import serializers

from .models import User


class UserSerializer(serializers.ModelSerializer):
    """Full serializer — ANO user management only.

    Role and is_active self-changes are rejected here so no code path can
    escalate privileges by accident.
    """

    class Meta:
        model = User
        fields = [
            "id", "username", "email", "first_name", "last_name",
            "roll_number", "role", "flight", "rank_title",
            "is_active", "is_staff",
        ]
        read_only_fields = ["id"]

    def validate_role(self, value):
        request = self.context.get("request")
        if request and self.instance and request.user.id == self.instance.id:
            if value != self.instance.role:
                raise serializers.ValidationError(
                    "You cannot change your own role."
                )
        return value

    def validate_is_active(self, value):
        request = self.context.get("request")
        if request and self.instance and request.user.id == self.instance.id:
            if not value:
                raise serializers.ValidationError(
                    "You cannot deactivate your own account."
                )
        return value

    def validate_flight(self, value):
        return (value or "").strip()


class UserDirectorySerializer(serializers.ModelSerializer):
    """Reduced user info safe to expose to every authenticated user."""

    display_name = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ["id", "username", "display_name", "role", "flight"]

    def get_display_name(self, obj):
        return obj.get_full_name() or obj.username
