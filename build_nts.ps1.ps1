# NTS complete build script
# Run from PowerShell:
# Set-ExecutionPolicy -Scope Process Bypass
# .\build_nts.ps1

$ErrorActionPreference = "Stop"
$ROOT = "C:\NCC_Progress Tracker\NTS"
$BACK = Join-Path $ROOT "backend"
$FRONT = Join-Path $ROOT "frontend"

function Write-File($Path, $Content) {
    $dir = Split-Path $Path -Parent
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    Set-Content -Path $Path -Value $Content -Encoding UTF8
}

# ---------- Django apps ----------
$apps = @("flights","attendance","fitness","tasks","certificates","notifications")
foreach ($app in $apps) {
    $p = Join-Path $BACK "apps\$app"
    if (!(Test-Path $p)) { New-Item -ItemType Directory -Force $p | Out-Null }
    New-Item -ItemType Directory -Force "$p\migrations","$p\management\commands" | Out-Null
    Write-File "$p\__init__.py" ""
    Write-File "$p\migrations\__init__.py" ""
    Write-File "$p\management\__init__.py" ""
    Write-File "$p\management\commands\__init__.py" ""
}

Write-File "$BACK\apps\flights\apps.py" @'
from django.apps import AppConfig
class FlightsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.flights"
'@

Write-File "$BACK\apps\flights\models.py" @'
from django.conf import settings
from django.db import models

class Flight(models.Model):
    name = models.CharField(max_length=100)
    code = models.CharField(max_length=20, unique=True)
    description = models.TextField(blank=True)
    flight_senior = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="managed_flights")
    active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    def __str__(self): return f"{self.name} ({self.code})"
'@

Write-File "$BACK\apps\flights\serializers.py" @'
from rest_framework import serializers
from .models import Flight
class FlightSerializer(serializers.ModelSerializer):
    member_count = serializers.IntegerField(read_only=True)
    class Meta:
        model = Flight
        fields = "__all__"
'@

Write-File "$BACK\apps\flights\views.py" @'
from django.db.models import Count
from rest_framework import permissions, viewsets
from rest_framework.exceptions import PermissionDenied
from apps.accounts.models import Role
from .models import Flight
from .serializers import FlightSerializer

class FlightViewSet(viewsets.ModelViewSet):
    queryset = Flight.objects.select_related("flight_senior").annotate(member_count=Count("cadets")).all()
    serializer_class = FlightSerializer
    permission_classes = [permissions.IsAuthenticated]
    def perform_create(self, serializer):
        if self.request.user.role not in {Role.ANO, Role.RANKED_SENIOR}: raise PermissionDenied("Only command staff can create flights.")
        serializer.save()
    def perform_update(self, serializer):
        if self.request.user.role not in {Role.ANO, Role.RANKED_SENIOR}: raise PermissionDenied("Only command staff can modify flights.")
        serializer.save()
    def perform_destroy(self, instance):
        if self.request.user.role != Role.ANO: raise PermissionDenied("Only ANO can delete flights.")
        instance.delete()
'@

Write-File "$BACK\apps\flights\urls.py" @'
from django.urls import include, path
from rest_framework.routers import DefaultRouter
from .views import FlightViewSet
router = DefaultRouter()
router.register("", FlightViewSet, basename="flight")
urlpatterns = [path("", include(router.urls))]
'@

Write-File "$BACK\apps\flights\admin.py" @'
from django.contrib import admin
from .models import Flight
@admin.register(Flight)
class FlightAdmin(admin.ModelAdmin):
    list_display = ("name","code","flight_senior","active")
    search_fields = ("name","code")
    list_filter = ("active",)
'@

Write-File "$BACK\apps\attendance\apps.py" @'
from django.apps import AppConfig
class AttendanceConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.attendance"
'@

Write-File "$BACK\apps\attendance\models.py" @'
from django.conf import settings
from django.db import models
from apps.cadets.models import Cadet

class AttendanceRecord(models.Model):
    class Status(models.TextChoices):
        PRESENT="PRESENT","Present"; ABSENT="ABSENT","Absent"; EXCUSED="EXCUSED","Excused"
    cadet = models.ForeignKey(Cadet,on_delete=models.CASCADE,related_name="attendance_records")
    date = models.DateField()
    status = models.CharField(max_length=20,choices=Status.choices)
    parade = models.ForeignKey("parades.Parade",null=True,blank=True,on_delete=models.SET_NULL,related_name="attendance_records")
    marked_by = models.ForeignKey(settings.AUTH_USER_MODEL,null=True,blank=True,on_delete=models.SET_NULL)
    notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    class Meta:
        constraints=[models.UniqueConstraint(fields=["cadet","date","parade"],name="unique_cadet_attendance")]
        ordering=["-date","cadet__name"]
'@

Write-File "$BACK\apps\attendance\serializers.py" @'
from rest_framework import serializers
from .models import AttendanceRecord
class AttendanceSerializer(serializers.ModelSerializer):
    cadet_name=serializers.CharField(source="cadet.name",read_only=True)
    roll_number=serializers.CharField(source="cadet.roll_number",read_only=True)
    class Meta:
        model=AttendanceRecord
        fields="__all__"
        read_only_fields=("marked_by","created_at")
'@

Write-File "$BACK\apps\attendance\views.py" @'
from django.db.models import Q
from rest_framework import permissions, viewsets
from rest_framework.exceptions import PermissionDenied
from apps.accounts.models import Role
from .models import AttendanceRecord
from .serializers import AttendanceSerializer

class AttendanceViewSet(viewsets.ModelViewSet):
    queryset=AttendanceRecord.objects.select_related("cadet","parade","marked_by").all()
    serializer_class=AttendanceSerializer
    permission_classes=[permissions.IsAuthenticated]
    def get_queryset(self):
        qs=super().get_queryset()
        q=self.request.query_params.get("search","").strip()
        date=self.request.query_params.get("date","")
        if q: qs=qs.filter(Q(cadet__name__icontains=q)|Q(cadet__roll_number__icontains=q))
        if date: qs=qs.filter(date=date)
        if self.request.user.role == Role.JUNIOR: qs=qs.filter(cadet__user=self.request.user)
        elif self.request.user.role in {Role.SENIOR,Role.FLIGHT_SENIOR}: qs=qs.filter(cadet__flight=self.request.user.flight)
        return qs
    def perform_create(self,serializer):
        if self.request.user.role not in {Role.ANO,Role.RANKED_SENIOR,Role.FLIGHT_SENIOR,Role.SENIOR}: raise PermissionDenied("You cannot mark attendance.")
        serializer.save(marked_by=self.request.user)
    def perform_update(self,serializer):
        if self.request.user.role not in {Role.ANO,Role.RANKED_SENIOR,Role.FLIGHT_SENIOR}: raise PermissionDenied("You cannot modify attendance.")
        serializer.save(marked_by=self.request.user)
'@

Write-File "$BACK\apps\attendance\urls.py" @'
from django.urls import include,path
from rest_framework.routers import DefaultRouter
from .views import AttendanceViewSet
router=DefaultRouter(); router.register("",AttendanceViewSet,basename="attendance")
urlpatterns=[path("",include(router.urls))]
'@

Write-File "$BACK\apps\attendance\admin.py" @'
from django.contrib import admin
from .models import AttendanceRecord
@admin.register(AttendanceRecord)
class AttendanceAdmin(admin.ModelAdmin):
    list_display=("cadet","date","status","parade","marked_by")
    search_fields=("cadet__name","cadet__roll_number")
    list_filter=("status","date")
'@

Write-File "$BACK\apps\fitness\apps.py" @'
from django.apps import AppConfig
class FitnessConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.fitness"
'@

Write-File "$BACK\apps\fitness\models.py" @'
from django.conf import settings
from django.db import models
from apps.cadets.models import Cadet
class FitnessRecord(models.Model):
    cadet=models.ForeignKey(Cadet,on_delete=models.CASCADE,related_name="fitness_records")
    assessment_date=models.DateField()
    assessment_type=models.CharField(max_length=100)
    score=models.DecimalField(max_digits=6,decimal_places=2,null=True,blank=True)
    status=models.CharField(max_length=30,default="ASSESSED")
    notes=models.TextField(blank=True)
    assessed_by=models.ForeignKey(settings.AUTH_USER_MODEL,null=True,blank=True,on_delete=models.SET_NULL)
    created_at=models.DateTimeField(auto_now_add=True)
    class Meta: ordering=["-assessment_date"]
'@

Write-File "$BACK\apps\fitness\serializers.py" @'
from rest_framework import serializers
from .models import FitnessRecord
class FitnessSerializer(serializers.ModelSerializer):
    cadet_name=serializers.CharField(source="cadet.name",read_only=True)
    class Meta:
        model=FitnessRecord
        fields="__all__"
        read_only_fields=("assessed_by","created_at")
'@

Write-File "$BACK\apps\fitness\views.py" @'
from rest_framework import permissions,viewsets
from rest_framework.exceptions import PermissionDenied
from apps.accounts.models import Role
from .models import FitnessRecord
from .serializers import FitnessSerializer
class FitnessViewSet(viewsets.ModelViewSet):
    queryset=FitnessRecord.objects.select_related("cadet","assessed_by").all()
    serializer_class=FitnessSerializer
    permission_classes=[permissions.IsAuthenticated]
    def get_queryset(self):
        qs=super().get_queryset()
        if self.request.user.role==Role.JUNIOR: qs=qs.filter(cadet__user=self.request.user)
        elif self.request.user.role in {Role.SENIOR,Role.FLIGHT_SENIOR}: qs=qs.filter(cadet__flight=self.request.user.flight)
        return qs
    def perform_create(self,serializer):
        if self.request.user.role not in {Role.ANO,Role.RANKED_SENIOR,Role.FLIGHT_SENIOR}: raise PermissionDenied("You cannot record fitness.")
        serializer.save(assessed_by=self.request.user)
    def perform_update(self,serializer):
        if self.request.user.role not in {Role.ANO,Role.RANKED_SENIOR,Role.FLIGHT_SENIOR}: raise PermissionDenied("You cannot modify fitness.")
        serializer.save(assessed_by=self.request.user)
'@

Write-File "$BACK\apps\fitness\urls.py" @'
from django.urls import include,path
from rest_framework.routers import DefaultRouter
from .views import FitnessViewSet
router=DefaultRouter(); router.register("",FitnessViewSet,basename="fitness")
urlpatterns=[path("",include(router.urls))]
'@

Write-File "$BACK\apps\fitness\admin.py" @'
from django.contrib import admin
from .models import FitnessRecord
@admin.register(FitnessRecord)
class FitnessAdmin(admin.ModelAdmin):
    list_display=("cadet","assessment_date","assessment_type","score","status")
    search_fields=("cadet__name","cadet__roll_number")
    list_filter=("status","assessment_type")
'@

Write-File "$BACK\apps\tasks\apps.py" @'
from django.apps import AppConfig
class TasksConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.tasks"
'@

Write-File "$BACK\apps\tasks\models.py" @'
from django.conf import settings
from django.db import models
class Task(models.Model):
    class Status(models.TextChoices):
        TODO="TODO","To Do"; IN_PROGRESS="IN_PROGRESS","In Progress"; COMPLETED="COMPLETED","Completed"; OVERDUE="OVERDUE","Overdue"
    class Priority(models.TextChoices):
        LOW="LOW","Low"; MEDIUM="MEDIUM","Medium"; HIGH="HIGH","High"
    title=models.CharField(max_length=200)
    description=models.TextField(blank=True)
    assignee=models.ForeignKey(settings.AUTH_USER_MODEL,null=True,blank=True,on_delete=models.SET_NULL,related_name="assigned_tasks")
    due_date=models.DateField(null=True,blank=True)
    priority=models.CharField(max_length=20,choices=Priority.choices,default=Priority.MEDIUM)
    status=models.CharField(max_length=30,choices=Status.choices,default=Status.TODO)
    completion_date=models.DateField(null=True,blank=True)
    created_by=models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.PROTECT,related_name="created_tasks")
    created_at=models.DateTimeField(auto_now_add=True)
    updated_at=models.DateTimeField(auto_now=True)
    class Meta: ordering=["status","due_date","-created_at"]
'@

Write-File "$BACK\apps\tasks\serializers.py" @'
from rest_framework import serializers
from .models import Task
class TaskSerializer(serializers.ModelSerializer):
    assignee_name=serializers.SerializerMethodField()
    def get_assignee_name(self,obj): return obj.assignee.get_full_name() or obj.assignee.username if obj.assignee else "Unassigned"
    class Meta:
        model=Task
        fields="__all__"
        read_only_fields=("created_by","created_at","updated_at")
'@

Write-File "$BACK\apps\tasks\views.py" @'
from rest_framework import permissions,viewsets
from rest_framework.exceptions import PermissionDenied
from apps.accounts.models import Role
from .models import Task
from .serializers import TaskSerializer
class TaskViewSet(viewsets.ModelViewSet):
    queryset=Task.objects.select_related("assignee","created_by").all()
    serializer_class=TaskSerializer
    permission_classes=[permissions.IsAuthenticated]
    def get_queryset(self):
        qs=super().get_queryset()
        if self.request.user.role==Role.JUNIOR: qs=qs.filter(assignee=self.request.user)
        elif self.request.user.role in {Role.SENIOR,Role.FLIGHT_SENIOR}: qs=qs.filter(assignee__flight=self.request.user.flight)
        return qs
    def perform_create(self,serializer):
        if self.request.user.role==Role.JUNIOR: raise PermissionDenied("Junior cannot create command tasks.")
        serializer.save(created_by=self.request.user)
    def perform_destroy(self,instance):
        if self.request.user.role not in {Role.ANO,Role.RANKED_SENIOR}: raise PermissionDenied("You cannot delete tasks.")
        instance.delete()
'@

Write-File "$BACK\apps\tasks\urls.py" @'
from django.urls import include,path
from rest_framework.routers import DefaultRouter
from .views import TaskViewSet
router=DefaultRouter(); router.register("",TaskViewSet,basename="task")
urlpatterns=[path("",include(router.urls))]
'@

Write-File "$BACK\apps\tasks\admin.py" @'
from django.contrib import admin
from .models import Task
@admin.register(Task)
class TaskAdmin(admin.ModelAdmin):
    list_display=("title","assignee","priority","status","due_date")
    search_fields=("title","description","assignee__username")
    list_filter=("priority","status")
'@

Write-File "$BACK\apps\certificates\apps.py" @'
from django.apps import AppConfig
class CertificatesConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.certificates"
'@

Write-File "$BACK\apps\certificates\models.py" @'
from django.conf import settings
from django.db import models
from apps.cadets.models import Cadet
class Certificate(models.Model):
    class Status(models.TextChoices):
        ISSUED="ISSUED","Issued"; REVOKED="REVOKED","Revoked"
    certificate_type=models.CharField(max_length=150)
    recipient=models.ForeignKey(Cadet,on_delete=models.PROTECT,related_name="certificates")
    issue_date=models.DateField()
    issuer=models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.PROTECT,related_name="issued_certificates")
    status=models.CharField(max_length=20,choices=Status.choices,default=Status.ISSUED)
    certificate_number=models.CharField(max_length=100,unique=True)
    notes=models.TextField(blank=True)
    created_at=models.DateTimeField(auto_now_add=True)
    class Meta: ordering=["-issue_date"]
'@

Write-File "$BACK\apps\certificates\serializers.py" @'
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
'@

Write-File "$BACK\apps\certificates\views.py" @'
from rest_framework import permissions,viewsets
from rest_framework.exceptions import PermissionDenied
from apps.accounts.models import Role
from .models import Certificate
from .serializers import CertificateSerializer
class CertificateViewSet(viewsets.ModelViewSet):
    queryset=Certificate.objects.select_related("recipient","issuer").all()
    serializer_class=CertificateSerializer
    permission_classes=[permissions.IsAuthenticated]
    def get_queryset(self):
        qs=super().get_queryset()
        if self.request.user.role==Role.JUNIOR: qs=qs.filter(recipient__user=self.request.user)
        elif self.request.user.role in {Role.SENIOR,Role.FLIGHT_SENIOR}: qs=qs.filter(recipient__flight=self.request.user.flight)
        return qs
    def perform_create(self,serializer):
        if self.request.user.role not in {Role.ANO,Role.RANKED_SENIOR}: raise PermissionDenied("Only command staff can issue certificates.")
        serializer.save(issuer=self.request.user)
'@

Write-File "$BACK\apps\certificates\urls.py" @'
from django.urls import include,path
from rest_framework.routers import DefaultRouter
from .views import CertificateViewSet
router=DefaultRouter(); router.register("",CertificateViewSet,basename="certificate")
urlpatterns=[path("",include(router.urls))]
'@

Write-File "$BACK\apps\certificates\admin.py" @'
from django.contrib import admin
from .models import Certificate
@admin.register(Certificate)
class CertificateAdmin(admin.ModelAdmin):
    list_display=("certificate_number","certificate_type","recipient","issue_date","issuer","status")
    search_fields=("certificate_number","recipient__name","recipient__roll_number")
    list_filter=("status","certificate_type")
'@

Write-File "$BACK\apps\notifications\apps.py" @'
from django.apps import AppConfig
class NotificationsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.notifications"
'@

Write-File "$BACK\apps\notifications\models.py" @'
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
'@

Write-File "$BACK\apps\notifications\serializers.py" @'
from rest_framework import serializers
from .models import Notification
class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model=Notification
        fields="__all__"
        read_only_fields=("recipient","created_at")
'@

Write-File "$BACK\apps\notifications\views.py" @'
from rest_framework import permissions,viewsets
from rest_framework.decorators import action
from rest_framework.response import Response
from .models import Notification
from .serializers import NotificationSerializer
class NotificationViewSet(viewsets.ModelViewSet):
    serializer_class=NotificationSerializer
    permission_classes=[permissions.IsAuthenticated]
    def get_queryset(self): return Notification.objects.filter(recipient=self.request.user)
    def perform_create(self,serializer): serializer.save(recipient=self.request.user)
    @action(detail=True,methods=["post"])
    def mark_read(self,request,pk=None):
        obj=self.get_object(); obj.read=True; obj.save(update_fields=["read"]); return Response(self.get_serializer(obj).data)
    @action(detail=False,methods=["post"])
    def mark_all_read(self,request):
        self.get_queryset().filter(read=False).update(read=True); return Response({"detail":"Notifications marked read."})
'@

Write-File "$BACK\apps\notifications\urls.py" @'
from django.urls import include,path
from rest_framework.routers import DefaultRouter
from .views import NotificationViewSet
router=DefaultRouter(); router.register("",NotificationViewSet,basename="notification")
urlpatterns=[path("",include(router.urls))]
'@

Write-File "$BACK\apps\notifications\admin.py" @'
from django.contrib import admin
from .models import Notification
@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display=("title","recipient","type","read","created_at")
    search_fields=("title","message","recipient__username")
    list_filter=("type","read")
'@

# ---------- Cadets API ----------
Write-File "$BACK\apps\cadets\serializers.py" @'
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
'@

Write-File "$BACK\apps\cadets\views.py" @'
from django.db.models import Q
from rest_framework import permissions,viewsets
from rest_framework.exceptions import PermissionDenied
from apps.accounts.models import Role
from .models import Cadet
from .serializers import CadetSerializer
class CadetViewSet(viewsets.ModelViewSet):
    queryset=Cadet.objects.select_related("user").prefetch_related("attendance_records","fitness_records","certificates").all()
    serializer_class=CadetSerializer
    permission_classes=[permissions.IsAuthenticated]
    def get_queryset(self):
        qs=super().get_queryset(); q=self.request.query_params.get("search","").strip(); flight=self.request.query_params.get("flight","").strip(); status=self.request.query_params.get("status","").strip(); role=self.request.query_params.get("role","").strip()
        if q: qs=qs.filter(Q(name__icontains=q)|Q(roll_number__icontains=q)|Q(rank__icontains=q))
        if flight: qs=qs.filter(flight__iexact=flight)
        if status: qs=qs.filter(status=status)
        if role: qs=qs.filter(role=role)
        if self.request.user.role==Role.JUNIOR: qs=qs.filter(user=self.request.user)
        elif self.request.user.role in {Role.SENIOR,Role.FLIGHT_SENIOR}: qs=qs.filter(Q(user=self.request.user)|Q(flight=self.request.user.flight))
        return qs
    def perform_create(self,serializer):
        if self.request.user.role not in {Role.ANO,Role.RANKED_SENIOR,Role.FLIGHT_SENIOR}: raise PermissionDenied("You do not have permission to create cadets.")
        serializer.save()
    def perform_update(self,serializer):
        if self.request.user.role not in {Role.ANO,Role.RANKED_SENIOR,Role.FLIGHT_SENIOR}: raise PermissionDenied("You do not have permission to modify cadets.")
        serializer.save()
    def perform_destroy(self,instance):
        if self.request.user.role not in {Role.ANO,Role.RANKED_SENIOR}: raise PermissionDenied("You do not have permission to delete cadets.")
        instance.delete()
'@

Write-File "$BACK\apps\cadets\urls.py" @'
from django.urls import include,path
from rest_framework.routers import DefaultRouter
from .views import CadetViewSet
router=DefaultRouter(); router.register("",CadetViewSet,basename="cadet")
urlpatterns=[path("",include(router.urls))]
'@

# ---------- Audit ----------
Write-File "$BACK\apps\audit\models.py" @'
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
'@

Write-File "$BACK\apps\audit\admin.py" @'
from django.contrib import admin
from .models import AuditLog
@admin.register(AuditLog)
class AuditAdmin(admin.ModelAdmin):
    list_display=("timestamp","actor","action","object_type","object_id")
    search_fields=("action","object_type","object_id","actor__username")
    list_filter=("action","object_type")
'@

Write-File "$BACK\apps\audit\utils.py" @'
from .models import AuditLog
def log_event(actor,action,obj=None,metadata=None):
    return AuditLog.objects.create(actor=actor,action=action,object_type=obj.__class__.__name__ if obj else "",object_id=str(getattr(obj,"pk","")) if obj else "",metadata=metadata or {})
'@

# ---------- Dashboard ----------
Write-File "$BACK\apps\dashboard\views.py" @'
from django.db.models import Count
from django.utils import timezone
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from apps.accounts.models import Role
from apps.cadets.models import Cadet
from apps.parades.models import Parade,VerificationStatus
from apps.attendance.models import AttendanceRecord
from apps.tasks.models import Task
from apps.fitness.models import FitnessRecord
class DashboardView(APIView):
    permission_classes=[IsAuthenticated]
    def get(self,request):
        total=Cadet.objects.filter(status="ACTIVE").count()
        attendance=list(AttendanceRecord.objects.all())
        attendance_pct=round(sum(1 for x in attendance if x.status in {"PRESENT","EXCUSED"})/len(attendance)*100,1) if attendance else 0
        assessed=FitnessRecord.objects.count()
        readiness=round(sum(float(x.score or 0) for x in FitnessRecord.objects.all())/assessed,1) if assessed else 0
        pending=Parade.objects.filter(verification_status=VerificationStatus.PENDING).count()
        upcoming=Parade.objects.filter(date__gte=timezone.localdate()).order_by("date","start_time")[:6]
        tasks=Task.objects.exclude(status="COMPLETED")
        return Response({
            "role":request.user.role,
            "permissions":{
                "can_verify_official":request.user.role==Role.ANO,
                "can_verify_unofficial":request.user.role==Role.RANKED_SENIOR,
                "can_create_parade":request.user.role!=Role.JUNIOR,
            },
            "statistics":{
                "total_cadets":total,
                "attendance_percentage":attendance_pct,
                "unit_readiness":readiness,
                "open_tasks":tasks.count(),
                "pending_verifications":pending,
                "upcoming_parades":upcoming.count(),
            },
            "upcoming_parades":[{
                "id":p.id,"title":p.title,"type":p.type,"date":p.date,"start_time":p.start_time,"location":p.location,"status":p.verification_status
            } for p in upcoming],
        })
'@

Write-File "$BACK\apps\dashboard\urls.py" @'
from django.urls import path
from .views import DashboardView
urlpatterns=[path("",DashboardView.as_view())]
'@

# ---------- Accounts role-safe serializer ----------
Write-File "$BACK\apps\accounts\serializers.py" @'
from rest_framework import serializers
from .models import User
class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model=User
        fields=["id","username","email","first_name","last_name","roll_number","role","flight","rank_title","is_active"]
        read_only_fields=["id"]
'@

# ---------- Main settings/urls additions ----------
$settingsPath="$BACK\config\settings.py"
$settings = Get-Content $settingsPath -Raw
$requiredApps = @('"apps.flights"','"apps.attendance"','"apps.fitness"','"apps.tasks"','"apps.certificates"','"apps.notifications"')
foreach($a in $requiredApps) {
    if($settings -notmatch [regex]::Escape($a)) {
        $settings = $settings -replace '("apps\.cadets",)', ('$1,' + $a)
    }
}
Write-File $settingsPath $settings

Write-File "$BACK\config\urls.py" @'
from django.contrib import admin
from django.urls import include,path
urlpatterns=[
 path("admin/",admin.site.urls),
 path("api/auth/",include("apps.accounts.urls")),
 path("api/parades/",include("apps.parades.urls")),
 path("api/dashboard/",include("apps.dashboard.urls")),
 path("api/cadets/",include("apps.cadets.urls")),
 path("api/flights/",include("apps.flights.urls")),
 path("api/attendance/",include("apps.attendance.urls")),
 path("api/fitness/",include("apps.fitness.urls")),
 path("api/tasks/",include("apps.tasks.urls")),
 path("api/certificates/",include("apps.certificates.urls")),
 path("api/notifications/",include("apps.notifications.urls")),
]
'@

# ---------- Seed demo ----------
Write-File "$BACK\apps\accounts\management\__init__.py" ""
Write-File "$BACK\apps\accounts\management\commands\__init__.py" ""
New-Item -ItemType Directory -Force "$BACK\apps\accounts\management\commands" | Out-Null
Write-File "$BACK\apps\accounts\management\commands\seed_demo.py" @'
from django.core.management.base import BaseCommand
from django.contrib.auth import get_user_model
from django.utils import timezone
from apps.accounts.models import Role
from apps.cadets.models import Cadet
from apps.flights.models import Flight
from apps.parades.models import Parade,ParadeType
from apps.attendance.models import AttendanceRecord
from apps.fitness.models import FitnessRecord
from apps.tasks.models import Task
from apps.certificates.models import Certificate
from apps.notifications.models import Notification

User=get_user_model()
class Command(BaseCommand):
    help="Create fictional NTS demo data"
    def handle(self,*args,**kwargs):
        users=[]
        demo=[("ano","ANO","Air Wing Officer"),("rs1","RANKED_SENIOR","Ranked Senior"),("fs1","FLIGHT_SENIOR","Flight Senior"),("senior1","SENIOR","Senior"),("panda","JUNIOR","Junior")]
        for username,role,title in demo:
            u,_=User.objects.get_or_create(username=username,defaults={"first_name":title,"role":role,"flight":"ALPHA","rank_title":title,"is_staff":role=="ANO"})
            u.role=role; u.flight="ALPHA"; u.set_password("NTSdemo123!"); u.save(); users.append(u)
        alpha,_=Flight.objects.get_or_create(code="ALPHA",defaults={"name":"Alpha Flight","flight_senior":users[2]})
        bravo,_=Flight.objects.get_or_create(code="BRAVO",defaults={"name":"Bravo Flight"})
        cadets=[]
        for i in range(1,9):
            u=users[4] if i==1 else None
            c,_=Cadet.objects.get_or_create(roll_number=f"NTS-{i:03}",defaults={"name":f"Demo Cadet {i}","role":"JUNIOR","flight":"ALPHA" if i<5 else "BRAVO","rank":"Cadet","status":"ACTIVE","user":u})
            cadets.append(c)
        today=timezone.localdate()
        Parade.objects.get_or_create(title="Weekly Training Parade",date=today,type=ParadeType.OFFICIAL,defaults={"start_time":"08:00","end_time":"10:00","location":"Air Wing Ground","description":"Official demo parade","created_by":users[0]})
        Parade.objects.get_or_create(title="Flight Drill Practice",date=today,type=ParadeType.UNOFFICIAL,defaults={"start_time":"15:00","end_time":"16:30","location":"Drill Square","description":"Unofficial demo parade","created_by":users[1]})
        for i,c in enumerate(cadets[:5]):
            AttendanceRecord.objects.get_or_create(cadet=c,date=today,parade=None,defaults={"status":"PRESENT" if i<4 else "ABSENT","marked_by":users[2]})
            FitnessRecord.objects.get_or_create(cadet=c,assessment_date=today,assessment_type="Readiness",defaults={"score":80+i*3,"status":"OPERATIONAL","assessed_by":users[2]})
        Task.objects.get_or_create(title="Prepare parade attendance sheet",defaults={"description":"Prepare the weekly attendance sheet.","assignee":users[3],"due_date":today,"priority":"HIGH","created_by":users[0]})
        Certificate.objects.get_or_create(certificate_number="NTS-DEMO-001",defaults={"certificate_type":"Participation","recipient":cadets[0],"issue_date":today,"issuer":users[0]})
        Notification.objects.get_or_create(recipient=users[0],title="Verification queue",defaults={"message":"Official parade is awaiting ANO verification.","type":"PARADE"})
        self.stdout.write(self.style.SUCCESS("NTS demo data created."))
        self.stdout.write("Demo accounts use password: NTSdemo123!")
'@

# ---------- Frontend complete replacement ----------
Write-File "$FRONT\src\App.jsx" @'
import React,{useEffect,useMemo,useState} from "react";
import {Activity,AlertCircle,BarChart3,CalendarDays,CheckCircle2,ClipboardCheck,FileBadge2,LayoutDashboard,LogOut,Menu,Plane,Plus,Search,ShieldCheck,Users,X} from "lucide-react";

const API="http://127.0.0.1:8000";
function apiFetch(path,options={}){
  const token=localStorage.getItem("nts_access");
  return fetch(API+path,{...options,headers:{"Content-Type":"application/json",...(token?{Authorization:`Bearer ${token}`}:{}) ,...(options.headers||{})}});
}
const nav=[
 ["Dashboard","dashboard",LayoutDashboard],["Parades","parades",CalendarDays],["Cadets","cadets",Users],["Attendance","attendance",ClipboardCheck],["Fitness","fitness",Activity],["Tasks","tasks",CheckCircle2],["Certificates","certificates",FileBadge2],["Notifications","notifications",AlertCircle]
];
function Badge({children,tone="slate"}){const m={green:"bg-emerald-50 text-emerald-700",red:"bg-red-50 text-red-700",blue:"bg-blue-50 text-blue-700",amber:"bg-amber-50 text-amber-700",slate:"bg-slate-100 text-slate-600"};return <span className={`rounded-full px-2.5 py-1 text-xs font-bold ${m[tone]||m.slate}`}>{children}</span>}
function Modal({title,onClose,children}){return <div className="fixed inset-0 z-50 grid place-items-center bg-slate-950/60 p-4"><div className="max-h-[92vh] w-full max-w-2xl overflow-auto rounded-3xl bg-white shadow-2xl"><div className="flex items-center justify-between border-b p-5"><h2 className="text-xl font-black text-slate-900">{title}</h2><button onClick={onClose} className="rounded-xl p-2 hover:bg-slate-100"><X/></button></div>{children}</div></div>}
function Login({onLogin}){const [username,setUsername]=useState("");const [password,setPassword]=useState("");const [error,setError]=useState("");async function submit(e){e.preventDefault();setError("");const r=await fetch(API+"/api/auth/login/",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({username,password})});const d=await r.json();if(!r.ok){setError(d.detail||"Login failed");return}localStorage.setItem("nts_access",d.access);localStorage.setItem("nts_user",JSON.stringify(d.user));onLogin(d.user)}return <div className="min-h-screen bg-slate-950 text-white grid place-items-center p-6"><div className="w-full max-w-md rounded-3xl border border-slate-700 bg-slate-900 p-8 shadow-2xl"><div className="mb-8 flex items-center gap-3"><div className="rounded-2xl bg-blue-600 p-3"><Plane/></div><div><div className="text-xs font-bold tracking-[.25em] text-blue-300">NCC AIR WING</div><div className="text-3xl font-black">NTS</div></div></div><h1 className="text-2xl font-black">Command access</h1><p className="mt-1 mb-6 text-sm text-slate-400">Training & Tracking System</p>{error&&<div className="mb-4 rounded-xl bg-red-500/10 p-3 text-sm text-red-300">{error}</div>}<form onSubmit={submit} className="space-y-4"><input value={username} onChange={e=>setUsername(e.target.value)} placeholder="Username" className="w-full rounded-xl bg-slate-800 px-4 py-3 outline-none ring-blue-500 focus:ring-2"/><input type="password" value={password} onChange={e=>setPassword(e.target.value)} placeholder="Password" className="w-full rounded-xl bg-slate-800 px-4 py-3 outline-none ring-blue-500 focus:ring-2"/><button className="w-full rounded-xl bg-blue-600 py-3 font-bold hover:bg-blue-500">Sign in</button></form><p className="mt-5 text-xs text-slate-500">Demo: panda / NTSdemo123!</p></div></div>}
function Dashboard({user}){const [d,setD]=useState(null);useEffect(()=>{apiFetch("/api/dashboard/").then(r=>r.json()).then(setD)},[]);if(!d)return <Loading/>;const s=d.statistics;return <Page title="Command Dashboard" eyebrow="Operations"><div className="grid gap-4 md:grid-cols-3 xl:grid-cols-6">{[["Cadets",s.total_cadets,Users],["Attendance",s.attendance_percentage+"%",ClipboardCheck],["Readiness",s.unit_readiness+"%",ShieldCheck],["Open tasks",s.open_tasks,CheckCircle2],["Pending",s.pending_verifications,AlertCircle],["Upcoming",s.upcoming_parades,CalendarDays]].map(([a,b,I])=><div className="rounded-2xl border bg-white p-5 shadow-sm" key={a}><I className="mb-5 text-blue-600"/><div className="text-3xl font-black text-slate-900">{b}</div><div className="text-sm text-slate-500">{a}</div></div>)}</div><div className="mt-6 grid gap-6 lg:grid-cols-2"><Panel title="Upcoming Parades">{d.upcoming_parades.length?d.upcoming_parades.map(p=><div key={p.id} className="flex items-center justify-between border-b py-4 last:border-0"><div><b>{p.title}</b><div className="text-xs text-slate-500">{p.date} · {p.location}</div></div><Badge tone={p.status==="VERIFIED"?"green":p.type==="OFFICIAL"?"blue":"amber"}>{p.type} · {p.status}</Badge></div>):<Empty text="No upcoming parades"/></Panel><Panel title="Command Hierarchy">{["ANO","Ranked Senior","Flight Senior","Senior","Junior"].map((x,i)=><div key={x} className="flex items-center gap-3 border-b py-3 last:border-0"><span className="grid h-8 w-8 place-items-center rounded-lg bg-slate-900 text-xs font-black text-white">{i+1}</span><b>{x}</b></div>)}</Panel></div></Page>}
function Page({title,eyebrow,action,children}){return <div><div className="mb-6 flex flex-col justify-between gap-4 md:flex-row md:items-end"><div><div className="text-xs font-black uppercase tracking-[.2em] text-blue-600">{eyebrow}</div><h1 className="mt-1 text-3xl font-black text-slate-950">{title}</h1></div>{action}</div>{children}</div>}
function Panel({title,children}){return <section className="rounded-2xl border bg-white p-5 shadow-sm"><h2 className="mb-2 text-lg font-black">{title}</h2>{children}</section>}
function Loading(){return <div className="rounded-2xl bg-white p-12 text-center text-slate-500">Loading…</div>}
function Empty({text}){return <div className="py-12 text-center text-sm text-slate-500">{text}</div>}
function CrudPage({title,eyebrow,path,columns,fields,canCreate=true}){const [rows,setRows]=useState([]),[loading,setLoading]=useState(true),[error,setError]=useState(""),[open,setOpen]=useState(false),[form,setForm]=useState({});async function load(){setLoading(true);const r=await apiFetch(path);const d=await r.json();if(!r.ok)setError(d.detail||"Unable to load data");else setRows(Array.isArray(d)?d:d.results||[]);setLoading(false)}useEffect(()=>{load()},[path]);function change(k,v){setForm(x=>({...x,[k]:v}))}async function save(e){e.preventDefault();const r=await apiFetch(path,{method:"POST",body:JSON.stringify(form)});const d=await r.json();if(!r.ok){setError(Object.values(d).flat().join(" ")||d.detail||"Save failed");return}setOpen(false);setForm({});load()}return <Page title={title} eyebrow={eyebrow} action={canCreate&&<button onClick={()=>setOpen(true)} className="rounded-xl bg-slate-950 px-4 py-3 font-bold text-white"><Plus className="mr-2 inline" size={18}/>Add</button>}>{error&&<div className="mb-4 rounded-xl bg-red-50 p-3 text-sm text-red-700">{error}</div>}<Panel title={`${rows.length} records`}>{loading?<Loading/>:rows.length===0?<Empty text={`No ${title.toLowerCase()} records yet.`}/>:<div className="overflow-x-auto"><table className="min-w-full"><thead><tr className="border-b text-left text-xs uppercase text-slate-500">{columns.map(c=><th className="px-3 py-3" key={c.k}>{c.l}</th>)}</tr></thead><tbody>{rows.map(r=><tr className="border-b last:border-0" key={r.id}>{columns.map(c=><td className="px-3 py-4 text-sm" key={c.k}>{c.render?c.render(r):r[c.k]??"—"}</td>)}</tr>)}</tbody></table></div>}</Panel>{open&&<Modal title={`Add ${title.slice(0,-1)}`} onClose={()=>setOpen(false)}><form onSubmit={save} className="space-y-4 p-6">{fields.map(f=><div key={f.k}><label className="mb-1 block text-sm font-bold">{f.l}</label>{f.type==="select"?<select value={form[f.k]||f.options[0].v} onChange={e=>change(f.k,e.target.value)} className="w-full rounded-xl border px-4 py-3">{f.options.map(o=><option value={o.v} key={o.v}>{o.l}</option>)}</select>:<input required={f.required} type={f.type||"text"} value={form[f.k]||""} onChange={e=>change(f.k,e.target.value)} className="w-full rounded-xl border px-4 py-3"/></div>)}<button className="w-full rounded-xl bg-blue-600 py-3 font-bold text-white">Create</button></form></Modal>}</Page>}
function Parades(){return <CrudPage title="Parades" eyebrow="Operations" path="/api/parades/" columns={[{k:"title",l:"Parade"},{k:"date",l:"Date"},{k:"type",l:"Type",render:r=><Badge tone={r.type==="OFFICIAL"?"blue":"amber"}>{r.type}</Badge>},{k:"verification_status",l:"Status",render:r=><Badge tone={r.verification_status==="VERIFIED"?"green":r.verification_status==="REJECTED"?"red":"amber"}>{r.verification_status}</Badge>},{k:"location",l:"Location"}]} fields={[{k:"title",l:"Title",required:true},{k:"type",l:"Type",type:"select",options:[{v:"OFFICIAL",l:"Official"},{v:"UNOFFICIAL",l:"Unofficial"}]},{k:"date",l:"Date",type:"date",required:true},{k:"start_time",l:"Start",type:"time",required:true},{k:"end_time",l:"End",type:"time",required:true},{k:"location",l:"Location",required:true},{k:"description",l:"Description"}]}/> }
function App(){const [user,setUser]=useState(()=>JSON.parse(localStorage.getItem("nts_user")||"null"));const [page,setPage]=useState("dashboard"),[mobile,setMobile]=useState(false);if(!user)return <Login onLogin={setUser}/>;const screens={dashboard:<Dashboard user={user}/>,parades:<Parades/>,cadets:<CrudPage title="Cadets" eyebrow="Personnel" path="/api/cadets/" columns={[{k:"name",l:"Cadet"},{k:"roll_number",l:"Roll No."},{k:"rank",l:"Rank"},{k:"role",l:"Role"},{k:"flight",l:"Flight"},{k:"status",l:"Status",render:r=><Badge tone={r.status==="ACTIVE"?"green":"slate"}>{r.status}</Badge>},{k:"attendance_percentage",l:"Attendance"}]} fields={[{k:"name",l:"Full name",required:true},{k:"roll_number",l:"Roll number",required:true},{k:"rank",l:"Rank"},{k:"role",l:"Role",type:"select",options:[{v:"JUNIOR",l:"Junior"},{v:"SENIOR",l:"Senior"},{v:"FLIGHT_SENIOR",l:"Flight Senior"},{v:"RANKED_SENIOR",l:"Ranked Senior"}]},{k:"flight",l:"Flight"},{k:"email",l:"Email",type:"email"},{k:"phone",l:"Phone"}]}/>,attendance:<CrudPage title="Attendance" eyebrow="Personnel" path="/api/attendance/" columns={[{k:"cadet_name",l:"Cadet"},{k:"roll_number",l:"Roll No."},{k:"date",l:"Date"},{k:"status",l:"Status",render:r=><Badge tone={r.status==="PRESENT"?"green":r.status==="ABSENT"?"red":"amber"}>{r.status}</Badge>}]} fields={[{k:"cadet",l:"Cadet ID",type:"number",required:true},{k:"date",l:"Date",type:"date",required:true},{k:"status",l:"Status",type:"select",options:[{v:"PRESENT",l:"Present"},{v:"ABSENT",l:"Absent"},{v:"EXCUSED",l:"Excused"}]},{k:"notes",l:"Notes"}]}/>,fitness:<CrudPage title="Fitness" eyebrow="Readiness" path="/api/fitness/" columns={[{k:"cadet_name",l:"Cadet"},{k:"assessment_date",l:"Date"},{k:"assessment_type",l:"Assessment"},{k:"score",l:"Score"},{k:"status",l:"Status"}]} fields={[{k:"cadet",l:"Cadet ID",type:"number",required:true},{k:"assessment_date",l:"Date",type:"date",required:true},{k:"assessment_type",l:"Assessment type",required:true},{k:"score",l:"Score",type:"number"},{k:"status",l:"Status",required:true},{k:"notes",l:"Notes"}]}/>,tasks:<CrudPage title="Tasks" eyebrow="Operations" path="/api/tasks/" columns={[{k:"title",l:"Task"},{k:"priority",l:"Priority"},{k:"status",l:"Status"},{k:"due_date",l:"Due"},{k:"assignee_name",l:"Assignee"}]} fields={[{k:"title",l:"Title",required:true},{k:"description",l:"Description"},{k:"assignee",l:"Assignee user ID",type:"number"},{k:"due_date",l:"Due date",type:"date"},{k:"priority",l:"Priority",type:"select",options:[{v:"LOW",l:"Low"},{v:"MEDIUM",l:"Medium"},{v:"HIGH",l:"High"}]}]}/>,certificates:<CrudPage title="Certificates" eyebrow="Recognition" path="/api/certificates/" columns={[{k:"certificate_number",l:"Number"},{k:"certificate_type",l:"Type"},{k:"recipient_name",l:"Recipient"},{k:"issue_date",l:"Issued"},{k:"status",l:"Status"}]} fields={[{k:"certificate_type",l:"Certificate type",required:true},{k:"recipient",l:"Cadet ID",type:"number",required:true},{k:"issue_date",l:"Issue date",type:"date",required:true},{k:"certificate_number",l:"Certificate number",required:true},{k:"notes",l:"Notes"}]}/>,notifications:<CrudPage title="Notifications" eyebrow="Command" path="/api/notifications/" columns={[{k:"title",l:"Notification"},{k:"type",l:"Type"},{k:"read",l:"Read",render:r=>r.read?"Yes":"No"},{k:"created_at",l:"Created"}]} fields={[]}/>} ;return <div className="min-h-screen bg-slate-100 text-slate-900"><aside className={`fixed inset-y-0 left-0 z-40 w-64 bg-slate-950 text-white transition-transform ${mobile?"translate-x-0":"-translate-x-full"} lg:translate-x-0`}><div className="flex h-20 items-center gap-3 border-b border-slate-800 px-5"><div className="rounded-xl bg-blue-600 p-2"><Plane size={20}/></div><div><div className="text-[10px] font-bold tracking-[.2em] text-blue-300">NCC AIR WING</div><b className="text-xl">NTS</b></div></div><nav className="p-3">{nav.map(([label,key,I])=><button key={key} onClick={()=>{setPage(key);setMobile(false)}} className={`mb-1 flex w-full items-center gap-3 rounded-xl px-4 py-3 text-sm font-semibold ${page===key?"bg-blue-600":"text-slate-300 hover:bg-slate-900"}`}><I size={18}/>{label}</button>)}</nav><div className="absolute bottom-0 w-full border-t border-slate-800 p-4"><div className="mb-3 text-xs text-slate-400">{user.first_name||user.username} · {user.role}</div><button onClick={()=>{localStorage.clear();setUser(null)}} className="flex items-center gap-2 text-sm text-slate-300"><LogOut size={16}/>Sign out</button></div></aside><div className="lg:pl-64"><header className="sticky top-0 z-30 flex h-20 items-center justify-between border-b bg-white/95 px-4 backdrop-blur md:px-8"><button onClick={()=>setMobile(!mobile)} className="rounded-xl p-2 lg:hidden"><Menu/></button><div className="font-black tracking-wide">NCC AIR WING COMMAND</div><div className="hidden items-center gap-3 md:flex"><div className="text-right"><b className="block text-sm">{user.first_name||user.username}</b><span className="text-xs text-slate-500">{user.role}</span></div><div className="grid h-10 w-10 place-items-center rounded-full bg-slate-900 font-bold text-white">{(user.first_name||user.username)[0].toUpperCase()}</div></div></header><main className="mx-auto max-w-7xl p-4 md:p-8">{screens[page]||screens.dashboard}</main></div></div>}
export default App;
'@

# ---------- Frontend CSS fallback ----------
if (Test-Path "$FRONT\src\index.css") {
$css = Get-Content "$FRONT\src\index.css" -Raw
if ($css -notmatch "font-family") { Write-File "$FRONT\src\index.css" @'
@tailwind base;
@tailwind components;
@tailwind utilities;
html,body,#root{min-height:100%;margin:0;font-family:Inter,ui-sans-serif,system-ui,sans-serif}
*{box-sizing:border-box}
'@ }
}

Write-Host ""
Write-Host "NTS files created successfully." -ForegroundColor Green
Write-Host ""
Write-Host "Next commands:" -ForegroundColor Cyan
Write-Host "cd `"$BACK`""
Write-Host ".\.venv\Scripts\Activate.ps1"
Write-Host "python manage.py makemigrations"
Write-Host "python manage.py migrate"
Write-Host "python manage.py seed_demo"
Write-Host "python manage.py check"
Write-Host ""
Write-Host "Frontend: cd `"$FRONT`"; npm run dev" -ForegroundColor Cyan
