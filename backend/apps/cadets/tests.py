import datetime as dt

from rest_framework.test import APITestCase

from apps.accounts.models import Role, User
from apps.cadets.models import Cadet


def make_user(role, username, flight="", **kw):
    return User.objects.create_user(username=username, role=role, flight=flight, password="pass12345", **kw)


class LoginAndMeTests(APITestCase):
    """Exercises the real JWT login flow end to end, through the actual URLs."""

    def setUp(self):
        self.user = make_user(Role.JUNIOR, "loginuser")

    def test_login_returns_tokens_and_user(self):
        resp = self.client.post("/api/auth/login/", {"username": "loginuser", "password": "pass12345"}, format="json")
        self.assertEqual(resp.status_code, 200)
        self.assertIn("access", resp.data)
        self.assertIn("refresh", resp.data)
        self.assertEqual(resp.data["user"]["role"], Role.JUNIOR)

    def test_wrong_password_is_rejected(self):
        resp = self.client.post("/api/auth/login/", {"username": "loginuser", "password": "wrong"}, format="json")
        self.assertEqual(resp.status_code, 401)

    def test_me_requires_authentication(self):
        resp = self.client.get("/api/auth/me/")
        self.assertEqual(resp.status_code, 401)

    def test_me_returns_the_logged_in_user(self):
        self.client.force_authenticate(self.user)
        resp = self.client.get("/api/auth/me/")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["username"], "loginuser")


class CadetVisibilityScopeTests(APITestCase):
    """The hierarchy visibility rule on /api/cadets/: ANO/Ranked Senior see every
    cadet; a Senior/Flight Senior sees only their own flight; a Junior sees only
    their own linked cadet profile."""

    def setUp(self):
        self.ano = make_user(Role.ANO, "ano_c")
        self.ranked = make_user(Role.RANKED_SENIOR, "rs_c")
        self.senior_alpha = make_user(Role.SENIOR, "sr_alpha", flight="Alpha")
        self.junior_alpha_user = make_user(Role.JUNIOR, "jr_alpha", flight="Alpha")
        self.junior_bravo_user = make_user(Role.JUNIOR, "jr_bravo", flight="Bravo")

        self.cadet_alpha = Cadet.objects.create(
            user=self.junior_alpha_user, name="Alpha Cadet", roll_number="A-001",
            flight="Alpha", joined_date=dt.date.today(),
        )
        self.cadet_bravo = Cadet.objects.create(
            user=self.junior_bravo_user, name="Bravo Cadet", roll_number="B-001",
            flight="Bravo", joined_date=dt.date.today(),
        )

    def _ids(self, user):
        self.client.force_authenticate(user)
        resp = self.client.get("/api/cadets/")
        self.assertEqual(resp.status_code, 200)
        data = resp.data["results"] if isinstance(resp.data, dict) and "results" in resp.data else resp.data
        return {c["id"] for c in data}

    def test_ano_sees_every_cadet(self):
        ids = self._ids(self.ano)
        self.assertEqual(ids, {self.cadet_alpha.id, self.cadet_bravo.id})

    def test_ranked_senior_sees_every_cadet(self):
        ids = self._ids(self.ranked)
        self.assertEqual(ids, {self.cadet_alpha.id, self.cadet_bravo.id})

    def test_senior_sees_only_their_own_flight(self):
        ids = self._ids(self.senior_alpha)
        self.assertEqual(ids, {self.cadet_alpha.id})

    def test_junior_sees_only_themselves(self):
        ids = self._ids(self.junior_alpha_user)
        self.assertEqual(ids, {self.cadet_alpha.id})

    def test_junior_cannot_create_a_cadet(self):
        self.client.force_authenticate(self.junior_alpha_user)
        resp = self.client.post("/api/cadets/", {
            "name": "New Cadet", "roll_number": "Z-999", "flight": "Alpha", "role": "JUNIOR",
        }, format="json")
        self.assertEqual(resp.status_code, 403)

    def test_ano_can_create_a_cadet(self):
        self.client.force_authenticate(self.ano)
        resp = self.client.post("/api/cadets/", {
            "name": "New Cadet", "roll_number": "Z-999", "flight": "Alpha", "role": "JUNIOR",
        }, format="json")
        self.assertEqual(resp.status_code, 201)
