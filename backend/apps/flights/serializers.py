from rest_framework import serializers
from .models import Flight
class FlightSerializer(serializers.ModelSerializer):
    member_count = serializers.IntegerField(read_only=True)
    class Meta:
        model = Flight
        fields = "__all__"
