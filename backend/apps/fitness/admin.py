from django.contrib import admin
from .models import FitnessRecord
@admin.register(FitnessRecord)
class FitnessAdmin(admin.ModelAdmin):
    list_display=("cadet","assessment_date","assessment_type","score","status")
    search_fields=("cadet__name","cadet__roll_number")
    list_filter=("status","assessment_type")
