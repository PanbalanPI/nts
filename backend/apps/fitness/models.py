from django.conf import settings
from django.db import models
from apps.cadets.models import Cadet
class FitnessRecord(models.Model):
    cadet=models.ForeignKey(Cadet,on_delete=models.CASCADE,related_name="fitness_records")
    assessment_date=models.DateField()
    assessment_type=models.CharField(max_length=100)
    score=models.DecimalField(max_digits=6,decimal_places=2,null=True,blank=True)
    status=models.CharField(max_length=30,default="ASSESSED")
    notes=models.TextField(blank=True)
    assessed_by=models.ForeignKey(settings.AUTH_USER_MODEL,null=True,blank=True,on_delete=models.SET_NULL)
    created_at=models.DateTimeField(auto_now_add=True)
    class Meta: ordering=["-assessment_date"]
