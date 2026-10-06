"""Fills a local RoomTrack backend (docker compose) with the demo data the app expects.

Run it once the backend is up:

    python tool/seed_backend.py

It talks only to the public API through the gateway, like the app does. Staff accounts need a second factor
(TOTP): the script enrolls an authenticator for the accounts it has to sign in with and writes their secrets to
tool/demo_accounts.local.json (git-ignored) so you can add them to Google Authenticator. The other staff accounts
enroll from the app on their first sign-in.

E-mail verification links are read from the notifications worker log (Email__Transport=Log in local development).
"""

import base64
import datetime as dt
import hashlib
import hmac
import json
import os
import re
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.request

API = os.environ.get("API_BASE_URL", "http://localhost:8080/api/v1").rstrip("/")
BACKEND_DIR = os.environ.get("ROOMTRACK_BACKEND_DIR", os.path.expanduser("~/RiderProjects/RoomTrack-BackEnd"))
STATE_FILE = os.path.join(os.path.dirname(__file__), "demo_accounts.local.json")

CHAIN_ADMIN = {"email": "cadena@roomtrack.pe", "password": "Cadena-RoomTrack-2026!"}
STAFF_PASSWORD = "RoomTrack-Staff-2026!"
GUEST_PASSWORD = "RoomTrack-Huesped-2026!"

STAFF = [
    {"email": "admin@roomtrack.pe", "firstName": "Ana", "lastName": "Torres", "role": "admin"},
    {"email": "recepcion@roomtrack.pe", "firstName": "Luis", "lastName": "Ramos", "role": "reception"},
    {"email": "limpieza@roomtrack.pe", "firstName": "María", "lastName": "Quispe", "role": "housekeeping"},
    {"email": "limpieza2@roomtrack.pe", "firstName": "Jorge", "lastName": "Díaz", "role": "housekeeping"},
    {"email": "mantenimiento@roomtrack.pe", "firstName": "Carlos", "lastName": "Vega", "role": "maintenance"},
]
GUESTS = [
    {"email": "huesped@roomtrack.pe", "firstName": "Sofía", "lastName": "Herrera"},
    {"email": "huesped2@roomtrack.pe", "firstName": "Andrés", "lastName": "Molina"},
]
ROOM_TYPES = [
    ("Estándar", "Habitación estándar con cama queen.", 95),
    ("Doble", "Dos camas, ideal para amigos o familia.", 140),
    ("Suite", "Suite con sala de estar y jacuzzi.", 205),
]
ROOMS = [
    ("101", "Estándar"), ("102", "Estándar"), ("103", "Estándar"), ("104", "Doble"),
    ("201", "Doble"), ("202", "Doble"), ("203", "Doble"), ("204", "Doble"),
    ("301", "Suite"), ("302", "Suite"), ("303", "Suite"), ("304", "Suite"),
]


class ApiError(Exception):
    def __init__(self, status, body, retry_after=None):
        super().__init__(f"HTTP {status}: {body}")
        self.status = status
        self.body = body
        self.retry_after = retry_after


def call(method, path, body=None, token=None):
    """JSON request through the gateway. Waits and retries when the rate limiter answers 429."""
    for attempt in range(8):
        try:
            return _call(method, path, body, token)
        except ApiError as error:
            if error.status != 429 or attempt == 7:
                raise
            wait = int(error.retry_after or 15)
            print(f"    (límite de intentos, espero {wait}s)")
            time.sleep(wait)


def _call(method, path, body=None, token=None):
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(API + path, data=data, method=method)
    request.add_header("Accept", "application/json")
    if body is not None:
        request.add_header("Content-Type", "application/json")
    if token:
        request.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        raw = error.read().decode(errors="replace")
        try:
            parsed = json.loads(raw)
        except ValueError:
            parsed = raw
        raise ApiError(error.code, parsed, error.headers.get("Retry-After")) from None


def totp(secret, at=None):
    key = base64.b32decode(secret.upper() + "=" * (-len(secret) % 8))
    counter = int((at or time.time()) // 30)
    digest = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    code = (struct.unpack(">I", digest[offset:offset + 4])[0] & 0x7FFFFFFF) % 1_000_000
    return f"{code:06d}"


def load_state():
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE, encoding="utf-8") as f:
            return json.load(f)
    return {"accounts": {}}


def save_state(state):
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2, ensure_ascii=False)


def sign_in(email, password, state):
    """Signs in, enrolling or answering the second factor when the account needs it. Returns the access token."""
    result = call("POST", "/authentication/sign-in", {"email": email, "password": password})
    if result.get("token"):
        return result["token"]
    account = state["accounts"].setdefault(email, {"password": password})
    if result.get("mfaEnrollmentRequired"):
        enrollment = call("POST", "/authentication/mfa/enrollment", token=result["mfaToken"])
        account["mfaSecret"] = enrollment["secret"]
        account["otpAuthUri"] = enrollment["otpAuthUri"]
        confirmed = call("POST", "/authentication/mfa/enrollment/confirm", {"code": totp(enrollment["secret"])},
                         token=result["mfaToken"])
        account["recoveryCodes"] = confirmed.get("recoveryCodes") or []
        save_state(state)
        return confirmed["token"]
    if result.get("mfaRequired"):
        secret = account.get("mfaSecret")
        if not secret:
            sys.exit(f"{email} ya tiene MFA pero su secreto no está en {STATE_FILE}.")
        for _ in range(3):
            try:
                return call("POST", "/authentication/mfa/verify", {"code": totp(secret)}, token=result["mfaToken"])["token"]
            except ApiError as error:
                # A code works once: wait for the next 30-second window.
                if not (isinstance(error.body, dict) and error.body.get("code") == "mfa.code_already_used"):
                    raise
                time.sleep(30 - time.time() % 30 + 1)
        raise RuntimeError(f"No pude completar el segundo factor de {email}.")
    raise RuntimeError(f"Respuesta de sign-in inesperada para {email}: {result}")


def verification_token(email, since):
    """Reads the verification link sent to `email` from the notifications worker log."""
    for _ in range(20):
        logs = subprocess.run(["docker", "compose", "logs", "--since", since, "notifications-worker"],
                              cwd=BACKEND_DIR, capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
        # Each logged e-mail shows its recipient before the body: take the first link after the last mention.
        position = logs.rfind(email)
        match = re.search(r"verify-email\?token=([A-Za-z0-9_\-%.]+)", logs[position:]) if position >= 0 else None
        if match:
            return urllib.request.unquote(match.group(1))
        time.sleep(1.5)
    raise RuntimeError(f"No encontré el enlace de verificación de {email} en el log del worker.")


def verify(email, since):
    call("POST", "/authentication/verify-email", {"token": verification_token(email, since)})


def ensure_user(token, user, password, hotel_id, since):
    try:
        created = call("POST", "/users", {**user, "password": password, "hotelId": hotel_id}, token=token)
        verify(user["email"], since)
        print(f"  + {user['role']:<13} {user['email']}")
        return created["id"]
    except ApiError as error:
        if error.status != 409:
            raise
        existing = [u for u in call("GET", "/users", token=token) if u["email"] == user["email"]][0]
        if not existing["emailVerified"]:
            # A previous run created it but did not get to verify it.
            resent_at = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            call("POST", "/authentication/verify-email/resend", {"email": user["email"]})
            verify(user["email"], resent_at)
            print(f"  ~ {user['role']:<13} {user['email']} (verificado ahora)")
        else:
            print(f"  = {user['role']:<13} {user['email']} (ya existía)")
        return existing["id"]


def first_name(options, fallback):
    """Catalog endpoints answer plain strings or objects with a name."""
    if not options:
        return fallback
    first = options[0]
    return first["name"] if isinstance(first, dict) else str(first)


def main():
    try:
        call("GET", "/room-types")
    except ApiError as error:
        if error.status not in (401, 403):
            raise
    except urllib.error.URLError:
        sys.exit(f"No hay backend en {API}. Levántalo con `docker compose up -d` en {BACKEND_DIR}.")

    state = load_state()
    since = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    print("Administrador de cadena")
    chain_token = sign_in(CHAIN_ADMIN["email"], CHAIN_ADMIN["password"], state)

    print("Administrador del hotel")
    admin = STAFF[0]
    ensure_user(chain_token, admin, STAFF_PASSWORD, None, since)
    admin_token = sign_in(admin["email"], STAFF_PASSWORD, state)

    me = call("GET", "/users/me", token=admin_token)
    hotel_id = me.get("hotelId")
    if hotel_id is None:
        hotel = call("POST", "/hotels", {
            "name": "Casa Aurora Boutique Hotel",
            "address": "Av. Larco 1150",
            "city": "Lima",
            "country": "Perú",
            "imageUrl": "https://images.unsplash.com/photo-1582719508461-905c673771fd?auto=format&fit=crop&w=1200&q=80",
            "description": "Hotel boutique con patio, piscina y 12 habitaciones.",
            "type": first_name(call("GET", "/accommodations/options/categories", token=admin_token), "Hotel"),
            "amenities": [],
        }, token=admin_token)
        hotel_id = hotel["hotel"]["id"]
        # The hotel was assigned to the admin, whose old tokens were revoked: use the renewed session.
        admin_token = hotel["session"]["token"]
        print(f"  + hotel {hotel_id}: Casa Aurora Boutique Hotel")
    else:
        print(f"  = hotel {hotel_id}")

    call("PUT", f"/hotels/{hotel_id}/payment-settings", {
        "accountHolder": "Casa Aurora SAC", "yapeNumber": "987654321", "plinNumber": "987654321",
    }, token=admin_token)

    print("Tipos de habitación y habitaciones")
    types = {t["name"]: t["id"] for t in call("GET", "/room-types", token=admin_token)}
    prices = {}
    for name, description, price in ROOM_TYPES:
        if name not in types:
            types[name] = call("POST", "/room-types", {"name": name, "description": description}, token=admin_token)["id"]
        prices[name] = price
    existing_rooms = {r["number"]: r for r in call("GET", "/rooms", token=admin_token) if r["hotelId"] == hotel_id}
    for number, type_name in ROOMS:
        if number in existing_rooms:
            continue
        existing_rooms[number] = call("POST", "/rooms", {
            "hotelId": hotel_id, "number": number, "roomTypeId": types[type_name], "price": prices[type_name],
            "description": f"Habitación {number} · {type_name}", "amenities": ["Wifi", "TV"],
        }, token=admin_token)
    print(f"  {len(existing_rooms)} habitaciones")

    print("Personal")
    for user in STAFF[1:]:
        ensure_user(admin_token, user, STAFF_PASSWORD, hotel_id, since)

    print("Huéspedes")
    guest_tokens = {}
    for guest in GUESTS:
        try:
            call("POST", "/authentication/sign-up", {**guest, "password": GUEST_PASSWORD, "role": "guest"})
            verify(guest["email"], since)
            print(f"  + {guest['email']}")
        except ApiError as error:
            if error.status != 409:
                raise
            print(f"  = {guest['email']} (ya existía)")
        guest_tokens[guest["email"]] = sign_in(guest["email"], GUEST_PASSWORD, state)

    print("Reservas")
    today = dt.date.today()
    bookings = [
        # Confirmed and paid: ready for the digital check-in from the app.
        ("huesped@roomtrack.pe", "304", 0, 3, True),
        # Pending payment: reception registers it from the app.
        ("huesped2@roomtrack.pe", "201", 0, 3, False),
    ]
    for email, number, start, nights, paid in bookings:
        token = guest_tokens[email]
        mine = [b for b in call("GET", "/bookings", token=token) if b["status"] not in ("Cancelled", "Completed")]
        if mine:
            print(f"  = {email} ya tiene la reserva {mine[0]['code']}")
            continue
        booking = call("POST", "/bookings", {
            "roomId": existing_rooms[number]["id"],
            "checkInDate": (today + dt.timedelta(days=start)).isoformat(),
            "checkOutDate": (today + dt.timedelta(days=start + nights)).isoformat(),
            "guestPhone": "999000111",
        }, token=token)
        if paid:
            call("POST", f"/bookings/{booking['id']}/payments", {"method": "Yape", "operationNumber": "000123"},
                 token=admin_token)
        print(f"  + {booking['code']} · hab. {number} · {email}{' · pagada' if paid else ' · pago pendiente'}")

    state["passwords"] = {"staff": STAFF_PASSWORD, "guest": GUEST_PASSWORD, "chainAdmin": CHAIN_ADMIN["password"]}
    save_state(state)
    print(f"\nListo. Cuentas y secretos MFA en {STATE_FILE}")


if __name__ == "__main__":
    main()
