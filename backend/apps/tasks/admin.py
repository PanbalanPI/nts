from django.contrib import admin
from .models import Task
@admin.register(Task)
class TaskAdmin(admin.ModelAdmin):
    list_display=("title","assignee","priority","status","due_date")
    search_fields=("title","description","assignee__username")
    list_filter=("priority","status")
