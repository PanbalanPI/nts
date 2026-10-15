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
