from rest_framework import serializers
from .models import Certificate
class CertificateSerializer(serializers.ModelSerializer):
    recipient_name=serializers.CharField(source="recipient.name",read_only=True)
    issuer_name=serializers.SerializerMethodField()
    def get_issuer_name(self,obj): return obj.issuer.get_full_name() or obj.issuer.username
    class Meta:
        model=Certificate
        fields="__all__"
        read_only_fields=("issuer","created_at")
