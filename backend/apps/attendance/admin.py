from django.contrib import admin
from .models import AttendanceRecord
@admin.register(AttendanceRecord)
class AttendanceAdmin(admin.ModelAdmin):
    list_display=("cadet","date","status","parade","marked_by")
    search_fields=("cadet__name","cadet__roll_number")
    list_filter=("status","date")
