from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from .models import User
@admin.register(User)
class NTSUserAdmin(UserAdmin):
    fieldsets=UserAdmin.fieldsets+(("NTS Profile",{"fields":("role","roll_number","flight","rank_title")}),)
    add_fieldsets=UserAdmin.add_fieldsets+(("NTS Profile",{"fields":("role","roll_number","flight","rank_title")}),)
    list_display=("username","email","roll_number","role","flight","is_active")
