from django.contrib.auth import authenticate
from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken

from apps.audit.utils import log_event
from apps.core.permissions import IsAno

from .models import Role, User
from .serializers import UserDirectorySerializer, UserSerializer


class LoginView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        user = authenticate(
            username=request.data.get("username", ""),
            password=request.data.get("password", ""),
        )
        if not user:
            return Response({"detail": "Invalid credentials."}, status=401)
        if not user.is_active:
            return Response({"detail": "This account is deactivated."}, status=403)

        refresh = RefreshToken.for_user(user)
        log_event(user, "USER_LOGIN", user, {"username": user.username})
        return Response({
            "access": str(refresh.access_token),
            "refresh": str(refresh),
            "user": UserSerializer(user, context={"request": request}).data,
        })


class LogoutView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        refresh_token = request.data.get("refresh")
        if refresh_token:
            try:
                token = RefreshToken(refresh_token)
                token.blacklist()
            except Exception:
                return Response({"detail": "Invalid refresh token."}, status=400)
        log_event(request.user, "USER_LOGOUT", request.user, {})
        return Response({"detail": "Logged out."})


class MeView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(UserSerializer(request.user, context={"request": request}).data)


class UserViewSet(viewsets.ModelViewSet):
    """Directory + ANO-only user management.

    LIST/RETRIEVE: every authenticated user gets the reduced directory form.
    CREATE/UPDATE/DELETE + set_role/set_active: ANO only.
    """

    queryset = User.objects.all().order_by("username")
    serializer_class = UserSerializer
    permission_classes = [IsAuthenticated]

    def get_permissions(self):
        if self.action in ("list", "retrieve"):
            return [IsAuthenticated()]
        return [IsAno()]

    def _is_ano(self):
        return self.request.user.role == Role.ANO

    def list(self, request, *args, **kwargs):
        qs = self.get_queryset()
        if not self._is_ano():
            return Response(UserDirectorySerializer(qs, many=True).data)
        return Response(UserSerializer(qs, many=True, context={"request": request}).data)

    def retrieve(self, request, *args, **kwargs):
        user = self.get_object()
        if not self._is_ano():
            return Response(UserDirectorySerializer(user).data)
        return Response(UserSerializer(user, context={"request": request}).data)

    def perform_create(self, serializer):
        user = serializer.save()
        log_event(self.request.user, "USER_CREATED", user,
                  {"username": user.username, "role": user.role})

    def perform_update(self, serializer):
        user = self.get_object()
        before_role, before_active = user.role, user.is_active
        updated = serializer.save()

        if updated.role != before_role:
            log_event(self.request.user, "USER_ROLE_CHANGED", updated,
                      {"from": before_role, "to": updated.role})
        if updated.is_active != before_active:
            log_event(self.request.user, "USER_ACTIVATION_CHANGED", updated,
                      {"is_active": updated.is_active})
        if not (updated.role != before_role or updated.is_active != before_active):
            log_event(self.request.user, "USER_UPDATED", updated, {"fields": "profile"})

    def perform_destroy(self, instance):
        raise PermissionDenied(
            "Users cannot be deleted. Deactivate them instead to preserve audit history."
        )

    @action(detail=True, methods=["post"])
    def set_role(self, request, pk=None):
        target = self.get_object()
        new_role = request.data.get("role")
        if new_role not in Role.values:
            raise ValidationError({"role": "Unknown role."})
        if target.role == new_role:
            return Response(self.get_serializer(target).data)
        old_role = target.role
        target.role = new_role
        target.save(update_fields=["role"])
        log_event(request.user, "USER_ROLE_CHANGED", target,
                  {"from": old_role, "to": new_role})
        return Response(self.get_serializer(target).data)

    @action(detail=True, methods=["post"])
    def set_active(self, request, pk=None):
        target = self.get_object()
        if target.id == request.user.id:
            raise ValidationError("You cannot deactivate your own account.")
        active = bool(request.data.get("is_active", True))
        if target.is_active != active:
            target.is_active = active
            target.save(update_fields=["is_active"])
            log_event(request.user, "USER_ACTIVATION_CHANGED", target,
                      {"is_active": active})
        return Response(self.get_serializer(target).data)
