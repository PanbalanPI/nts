from django.urls import include,path
from rest_framework.routers import DefaultRouter
from .views import FitnessViewSet
router=DefaultRouter(); router.register("",FitnessViewSet,basename="fitness")
urlpatterns=[path("",include(router.urls))]
