from django.conf import settings
from django.db import models
from apps.cadets.models import Cadet

class AttendanceRecord(models.Model):
    class Status(models.TextChoices):
        PRESENT="PRESENT","Present"; ABSENT="ABSENT","Absent"; EXCUSED="EXCUSED","Excused"
    cadet = models.ForeignKey(Cadet,on_delete=models.CASCADE,related_name="attendance_records")
    date = models.DateField()
    status = models.CharField(max_length=20,choices=Status.choices)
    parade = models.ForeignKey("parades.Parade",null=True,blank=True,on_delete=models.SET_NULL,related_name="attendance_records")
    marked_by = models.ForeignKey(settings.AUTH_USER_MODEL,null=True,blank=True,on_delete=models.SET_NULL)
    notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    class Meta:
        constraints=[models.UniqueConstraint(fields=["cadet","date","parade"],name="unique_cadet_attendance")]
        ordering=["-date","cadet__name"]
