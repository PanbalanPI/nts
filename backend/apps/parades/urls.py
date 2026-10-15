from django.urls import include,path
from rest_framework.routers import DefaultRouter
from .views import ParadeViewSet
router=DefaultRouter(); router.register("",ParadeViewSet,basename="parade")
urlpatterns=[path("",include(router.urls))]
