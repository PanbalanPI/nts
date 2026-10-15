from django.db.models import Q
from rest_framework import viewsets
from rest_framework.exceptions import PermissionDenied

from apps.accounts.models import Role
from apps.audit.utils import log_event
from apps.notifications.services import notify
from apps.core.permissions import scope_queryset_by_role

from .models import Task
from .serializers import TaskSerializer

CREATE_ROLES = {Role.ANO, Role.RANKED_SENIOR, Role.FLIGHT_SENIOR, Role.SENIOR}
DELETE_ROLES = {Role.ANO, Role.RANKED_SENIOR}


class TaskViewSet(viewsets.ModelViewSet):
    queryset = Task.objects.select_related("assignee", "created_by").all()
    serializer_class = TaskSerializer

    def get_queryset(self):
        qs = super().get_queryset()
        status_param = self.request.query_params.get("status", "").strip()
        if status_param:
            qs = qs.filter(status=status_param)
        return scope_queryset_by_role(
            qs,
            self.request.user,
            junior_filter=lambda u: Q(assignee=u),
            staff_filter=lambda u: (
                Q(assignee=u) | Q(assignee__flight=u.flight)
                if u.flight else Q(assignee=u)
            ),
        )

    def _assert_assignee_in_scope(self, assignee):
        """Command staff may assign anywhere; others only within their flight."""
        user = self.request.user
        if user.role in (Role.ANO, Role.RANKED_SENIOR):
            return
        if assignee and assignee.flight != user.flight:
            raise PermissionDenied("You can only assign tasks within your own flight.")

    def perform_create(self, serializer):
        if self.request.user.role not in CREATE_ROLES:
            raise PermissionDenied("Juniors cannot create command tasks.")
        assignee = serializer.validated_data.get("assignee")
        self._assert_assignee_in_scope(assignee)
        task = serializer.save(created_by=self.request.user)
        log_event(self.request.user, "TASK_CREATED", task, {"title": task.title})
        if assignee:
            notify(assignee, title="New task assigned",
                   message=f"You were assigned: {task.title}", ntype="TASK")
            log_event(self.request.user, "TASK_ASSIGNED", task, {"assignee": assignee.username})

    def perform_update(self, serializer):
        task = self.get_object()
        user = self.request.user
        if user.role == Role.JUNIOR and task.assignee_id != user.id:
            raise PermissionDenied("Juniors can only update their own tasks.")

        new_assignee = serializer.validated_data.get("assignee")
        if new_assignee and new_assignee != task.assignee:
            if user.role == Role.JUNIOR:
                raise PermissionDenied("Juniors cannot reassign tasks.")
            self._assert_assignee_in_scope(new_assignee)
            log_event(user, "TASK_ASSIGNED", task, {"assignee": new_assignee.username})
            notify(new_assignee, title="New task assigned",
                   message=f"You were assigned: {task.title}", ntype="TASK")

        previous_status = task.status
        updated = serializer.save()
        log_event(user, "TASK_UPDATED", updated, {"status": updated.status})
        if previous_status != Task.Status.COMPLETED and updated.status == Task.Status.COMPLETED:
            log_event(user, "TASK_COMPLETED", updated, {"title": updated.title})
            if updated.created_by:
                notify(updated.created_by, title="Task completed",
                       message=f"{updated.title} was completed.", ntype="TASK")

    def perform_destroy(self, instance):
        if self.request.user.role not in DELETE_ROLES:
            raise PermissionDenied("You cannot delete tasks.")
        log_event(self.request.user, "TASK_DELETED", None, {"title": instance.title})
        instance.delete()
