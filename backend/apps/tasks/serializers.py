from rest_framework import serializers

from .models import Task


class TaskSerializer(serializers.ModelSerializer):
    assignee_name = serializers.SerializerMethodField()
    is_overdue = serializers.BooleanField(read_only=True)
    effective_status = serializers.CharField(read_only=True)

    class Meta:
        model = Task
        fields = [
            "id", "title", "description", "assignee", "assignee_name",
            "due_date", "priority", "status", "is_overdue", "effective_status",
            "completion_date", "created_by", "created_at", "updated_at",
        ]
        read_only_fields = ["created_by", "created_at", "updated_at", "completion_date"]

    def get_assignee_name(self, obj):
        if not obj.assignee:
            return "Unassigned"
        return obj.assignee.get_full_name() or obj.assignee.username

    def validate_status(self, value):
        # OVERDUE is derived, never client-writable.
        if value == Task.Status.OVERDUE:
            raise serializers.ValidationError(
                "OVERDUE is computed automatically for tasks past their due date."
            )
        return value
