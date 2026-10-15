from django.contrib import admin
from .models import Certificate
@admin.register(Certificate)
class CertificateAdmin(admin.ModelAdmin):
    list_display=("certificate_number","certificate_type","recipient","issue_date","issuer","status")
    search_fields=("certificate_number","recipient__name","recipient__roll_number")
    list_filter=("status","certificate_type")
