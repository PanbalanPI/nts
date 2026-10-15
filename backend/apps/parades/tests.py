import datetime as dt

from django.test import TestCase
from rest_framework.exceptions import PermissionDenied, ValidationError

from apps.accounts.models import Role, User
from apps.audit.models import AuditLog
from apps.parades.models import Parade, ParadeType, VerificationStatus
from apps.parades.services import verify_parade


def make_user(role, username, **kw):
    return User.objects.create_user(username=username, role=role, password="x", **kw)


class ParadeVerificationRuleTests(TestCase):
    """Covers the 9 mandatory scenarios from the spec. Each test name maps 1:1
    to a numbered requirement so coverage is easy to audit."""

    def setUp(self):
        self.ano = make_user(Role.ANO, "ano1")
        self.ranked = make_user(Role.RANKED_SENIOR, "rs1")
        self.ranked2 = make_user(Role.RANKED_SENIOR, "rs2")
        self.flight_senior = make_user(Role.FLIGHT_SENIOR, "fs1")
        self.senior = make_user(Role.SENIOR, "sr1")
        self.junior = make_user(Role.JUNIOR, "jr1")

    def _parade(self, parade_type, created_by):
        return Parade.objects.create(
            title="Test Parade", type=parade_type, date=dt.date.today(),
            start_time=dt.time(7, 0), end_time=dt.time(8, 0), location="Ground", created_by=created_by,
        )

    # 1. Official parade requires ANO verification.
    def test_official_parade_requires_ano(self):
        parade = self._parade(ParadeType.OFFICIAL, self.ranked)
        verify_parade(parade, self.ano, approved=True)
        parade.refresh_from_db()
        self.assertEqual(parade.verification_status, VerificationStatus.VERIFIED)
        self.assertEqual(parade.verified_by, self.ano)

    # 2. Ranked Senior cannot verify an official parade.
    def test_ranked_senior_cannot_verify_official(self):
        parade = self._parade(ParadeType.OFFICIAL, self.ano)
        with self.assertRaises(PermissionDenied):
            verify_parade(parade, self.ranked, approved=True)
        parade.refresh_from_db()
        self.assertEqual(parade.verification_status, VerificationStatus.PENDING)

    # 3. Unofficial parade requires Ranked Senior verification.
    def test_unofficial_parade_requires_ranked_senior(self):
        parade = self._parade(ParadeType.UNOFFICIAL, self.senior)
        verify_parade(parade, self.ranked, approved=True)
        parade.refresh_from_db()
        self.assertEqual(parade.verification_status, VerificationStatus.VERIFIED)
        self.assertEqual(parade.verified_by, self.ranked)

    # 4. ANO can verify official parade.
    def test_ano_can_verify_official_parade(self):
        parade = self._parade(ParadeType.OFFICIAL, self.flight_senior)
        result = verify_parade(parade, self.ano, approved=True, reason="Looks good")
        self.assertEqual(result.verification_status, VerificationStatus.VERIFIED)
        self.assertEqual(result.verification_reason, "Looks good")

    # 5. Ranked Senior can verify unofficial parade (approval + rejection paths).
    def test_ranked_senior_can_verify_unofficial_parade(self):
        approved = self._parade(ParadeType.UNOFFICIAL, self.senior)
        verify_parade(approved, self.ranked, approved=True)
        approved.refresh_from_db()
        self.assertEqual(approved.verification_status, VerificationStatus.VERIFIED)

        rejected = self._parade(ParadeType.UNOFFICIAL, self.senior)
        verify_parade(rejected, self.ranked, approved=False, reason="Clashes with exams")
        rejected.refresh_from_db()
        self.assertEqual(rejected.verification_status, VerificationStatus.REJECTED)
        self.assertEqual(rejected.verification_reason, "Clashes with exams")

    # 6. Junior cannot verify either parade type.
    def test_junior_cannot_verify_any_parade(self):
        official = self._parade(ParadeType.OFFICIAL, self.ano)
        unofficial = self._parade(ParadeType.UNOFFICIAL, self.senior)
        with self.assertRaises(PermissionDenied):
            verify_parade(official, self.junior, approved=True)
        with self.assertRaises(PermissionDenied):
            verify_parade(unofficial, self.junior, approved=True)

    # 7. Unauthorized roles cannot bypass verification, regardless of who created the parade.
    def test_unauthorized_roles_cannot_bypass_verification(self):
        official = self._parade(ParadeType.OFFICIAL, self.ano)
        for actor in (self.flight_senior, self.senior, self.junior, self.ranked):
            with self.assertRaises(PermissionDenied):
                verify_parade(official, actor, approved=True)
        official.refresh_from_db()
        self.assertEqual(official.verification_status, VerificationStatus.PENDING)

    # 8. Invalid status transitions are rejected (already-decided parade cannot be re-verified).
    def test_invalid_status_transition_is_rejected(self):
        parade = self._parade(ParadeType.OFFICIAL, self.ranked)
        verify_parade(parade, self.ano, approved=True)
        parade.refresh_from_db()
        with self.assertRaises(ValidationError):
            verify_parade(parade, self.ano, approved=False, reason="too late")
        parade.refresh_from_db()
        self.assertEqual(parade.verification_status, VerificationStatus.VERIFIED)  # unchanged

    # 9. A rejection without a reason is rejected (model/service-level validation).
    def test_rejection_requires_a_reason(self):
        parade = self._parade(ParadeType.UNOFFICIAL, self.senior)
        with self.assertRaises(ValidationError):
            verify_parade(parade, self.ranked, approved=False, reason="")
        parade.refresh_from_db()
        self.assertEqual(parade.verification_status, VerificationStatus.PENDING)


class ParadeCreationRuleTests(TestCase):
    """The create-time rules enforced in ParadeViewSet.perform_create, exercised
    directly against the model/service layer so they don't depend on the HTTP stack."""

    def setUp(self):
        self.ano = make_user(Role.ANO, "ano2")
        self.ranked = make_user(Role.RANKED_SENIOR, "rs3")
        self.senior = make_user(Role.SENIOR, "sr2")
        self.junior = make_user(Role.JUNIOR, "jr2")

    def test_junior_cannot_be_the_designated_official_verifier(self):
        # Sanity check on the role mapping itself, independent of the view layer.
        parade = Parade.objects.create(
            title="X", type=ParadeType.OFFICIAL, date=dt.date.today(),
            start_time=dt.time(7, 0), end_time=dt.time(8, 0), location="Ground", created_by=self.ranked,
        )
        self.assertEqual(parade.required_verifier_role(), Role.ANO)
        self.assertFalse(parade.can_be_verified_by(self.junior))
        self.assertTrue(parade.can_be_verified_by(self.ano))
