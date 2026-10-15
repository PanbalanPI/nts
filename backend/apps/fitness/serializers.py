from rest_framework import serializers
from .models import FitnessRecord
class FitnessSerializer(serializers.ModelSerializer):
    cadet_name=serializers.CharField(source="cadet.name",read_only=True)
    class Meta:
        model=FitnessRecord
        fields="__all__"
        read_only_fields=("assessed_by","created_at")
