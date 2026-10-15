from django.conf import settings
from django.db import models
class Notification(models.Model):
    class Type(models.TextChoices):
        PARADE="PARADE","Parade"; TASK="TASK","Task"; ATTENDANCE="ATTENDANCE","Attendance"; FITNESS="FITNESS","Fitness"; CERTIFICATE="CERTIFICATE","Certificate"; SYSTEM="SYSTEM","System"
    recipient=models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.CASCADE,related_name="notifications")
    title=models.CharField(max_length=200)
    message=models.TextField()
    type=models.CharField(max_length=30,choices=Type.choices,default=Type.SYSTEM)
    read=models.BooleanField(default=False)
    created_at=models.DateTimeField(auto_now_add=True)
    class Meta: ordering=["-created_at"]
