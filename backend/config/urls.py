from django.contrib import admin
from django.urls import include, path

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/auth/", include("apps.accounts.urls")),
    path("api/parades/", include("apps.parades.urls")),
    path("api/dashboard/", include("apps.dashboard.urls")),
    path("api/cadets/", include("apps.cadets.urls")),
    path("api/flights/", include("apps.flights.urls")),
    path("api/attendance/", include("apps.attendance.urls")),
    path("api/fitness/", include("apps.fitness.urls")),
    path("api/tasks/", include("apps.tasks.urls")),
    path("api/certificates/", include("apps.certificates.urls")),
    path("api/notifications/", include("apps.notifications.urls")),
    path("api/audit/", include("apps.audit.urls")),
]

handler400 = "config.error_views.bad_request"
handler403 = "config.error_views.forbidden"
handler404 = "config.error_views.not_found"
handler500 = "config.error_views.server_error"
