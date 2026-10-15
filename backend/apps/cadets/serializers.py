from rest_framework import serializers
from .models import Cadet
class CadetSerializer(serializers.ModelSerializer):
    attendance_percentage=serializers.SerializerMethodField()
    readiness_status=serializers.SerializerMethodField()
    task_status=serializers.SerializerMethodField()
    certificate_status=serializers.SerializerMethodField()
    class Meta:
        model=Cadet
        fields=["id","user","name","roll_number","rank","role","flight","phone","email","status","joined_date","notes","attendance_percentage","readiness_status","task_status","certificate_status","created_at","updated_at"]
        read_only_fields=["created_at","updated_at","attendance_percentage","readiness_status","task_status","certificate_status"]
    def get_attendance_percentage(self,obj):
        records=list(obj.attendance_records.all())
        if not records:return 0
        return round(sum(1 for r in records if r.status in {"PRESENT","EXCUSED"})/len(records)*100,1)
    def get_readiness_status(self,obj):
        latest=obj.fitness_records.order_by("-assessment_date").first()
        return latest.status if latest else "Not assessed"
    def get_task_status(self,obj): return "View tasks"
    def get_certificate_status(self,obj): return f"{obj.certificates.count()} issued"
