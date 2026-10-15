from rest_framework import serializers
from .models import AttendanceRecord
class AttendanceSerializer(serializers.ModelSerializer):
    cadet_name=serializers.CharField(source="cadet.name",read_only=True)
    roll_number=serializers.CharField(source="cadet.roll_number",read_only=True)
    class Meta:
        model=AttendanceRecord
        fields="__all__"
        read_only_fields=("marked_by","created_at")
