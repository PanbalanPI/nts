from django.contrib import admin

from .models import Parade


@admin.register(Parade)
class ParadeAdmin(admin.ModelAdmin):
    list_display = (
        "title", "type", "date", "state", "verification_status",
        "verified_by", "verified_at", "created_by",
    )
    search_fields = ("title", "location", "created_by__username")
    list_filter = ("type", "state", "date")
    readonly_fields = ("created_at", "verified_at", "cancelled_at", "completed_at")
    ordering = ("-date", "-start_time")
