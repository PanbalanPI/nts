from rest_framework import serializers

from .models import Parade, ParadeState, VerificationStatus


class ParadeSerializer(serializers.ModelSerializer):
    created_by_name = serializers.CharField(
        source="created_by.get_full_name", read_only=True, default=""
    )
    verified_by_name = serializers.CharField(
        source="verified_by.get_full_name", read_only=True, default=""
    )
    required_verifier_role = serializers.CharField(read_only=True)

    class Meta:
        model = Parade
        fields = [
            "id",
            "title",
            "type",
            "date",
            "start_time",
            "end_time",
            "location",
            "description",
            "created_by",
            "created_by_name",
            "state",
            "verification_status",
            "verified_by",
            "verified_by_name",
            "verification_reason",
            "verified_at",
            "cancelled_at",
            "completed_at",
            "required_verifier_role",
            "created_at",
        ]
        read_only_fields = [
            "created_by",
            "state",
            "verification_status",
            "verified_by",
            "verification_reason",
            "verified_at",
            "cancelled_at",
            "completed_at",
            "created_at",
        ]

    def validate(self, attrs):
        # Force every newly created parade to start in the draft state.
        if self.instance is None:
            attrs["state"] = ParadeState.DRAFT
            attrs["verification_status"] = VerificationStatus.PENDING
        return attrs
