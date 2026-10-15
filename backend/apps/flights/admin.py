from django.contrib import admin
from .models import Flight
@admin.register(Flight)
class FlightAdmin(admin.ModelAdmin):
    list_display = ("name","code","flight_senior","active")
    search_fields = ("name","code")
    list_filter = ("active",)
