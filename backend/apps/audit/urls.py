from rest_framework import routers

from .views import AuditLogViewSet

router = routers.DefaultRouter()
router.register("", AuditLogViewSet, basename="auditlog")

urlpatterns = router.urls
