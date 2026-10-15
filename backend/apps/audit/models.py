from django.conf import settings
from django.db import models
class AuditLog(models.Model):
    actor=models.ForeignKey(settings.AUTH_USER_MODEL,null=True,blank=True,on_delete=models.SET_NULL,related_name="audit_events")
    action=models.CharField(max_length=100)
    object_type=models.CharField(max_length=100,blank=True)
    object_id=models.CharField(max_length=100,blank=True)
    metadata=models.JSONField(default=dict,blank=True)
    timestamp=models.DateTimeField(auto_now_add=True)
    class Meta: ordering=["-timestamp"]
