from django.conf import settings
from django.db import models
from apps.cadets.models import Cadet
class Certificate(models.Model):
    class Status(models.TextChoices):
        ISSUED="ISSUED","Issued"; REVOKED="REVOKED","Revoked"
    certificate_type=models.CharField(max_length=150)
    recipient=models.ForeignKey(Cadet,on_delete=models.PROTECT,related_name="certificates")
    issue_date=models.DateField()
    issuer=models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.PROTECT,related_name="issued_certificates")
    status=models.CharField(max_length=20,choices=Status.choices,default=Status.ISSUED)
    certificate_number=models.CharField(max_length=100,unique=True)
    notes=models.TextField(blank=True)
    created_at=models.DateTimeField(auto_now_add=True)
    class Meta: ordering=["-issue_date"]
