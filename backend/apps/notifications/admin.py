from django.contrib import admin
from .models import Notification
@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display=("title","recipient","type","read","created_at")
    search_fields=("title","message","recipient__username")
    list_filter=("type","read")
