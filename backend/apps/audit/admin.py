from django.contrib import admin

from .models import AuditLog


@admin.register(AuditLog)
class AuditAdmin(admin.ModelAdmin):
    """Append-only: audit records are viewable but never editable/deletable."""

    list_display = ("timestamp", "actor", "action", "object_type", "object_id")
    search_fields = ("action", "object_type", "object_id", "actor__username")
    list_filter = ("action", "object_type")
    readonly_fields = ("actor", "action", "object_type", "object_id", "metadata", "timestamp")
    ordering = ("-timestamp",)

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
