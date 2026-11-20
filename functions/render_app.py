
import os
import hmac
import time
import json
import base64
import hashlib

from flask import Flask, jsonify, request
from main import (
    nearby_emergency_alert,
    nearby_emergency_details,
    register_pending_emergency,
    process_overdue_pending_alerts,
    db,
)

app = Flask(__name__)

ALLOWED_ORIGIN = "https://serene-bavarois-063032.netlify.app"


@app.before_request
def handle_preflight():
    if request.method == "OPTIONS":
        return "", 204


@app.after_request
def add_cors_headers(response):
    origin = request.headers.get("Origin")

    if origin == ALLOWED_ORIGIN:
        response.headers["Access-Control-Allow-Origin"] = ALLOWED_ORIGIN
        response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
        response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
        response.headers["Vary"] = "Origin"

    return response

OFFICERS = {
    "KL-PO-1041": {
        "name": "Rajesh Kumar",
        "role": "Police Officer",
        "password_env": "OFFICER_KL_PO_1041_PASSWORD",
    },
    "KL-PO-2275": {
        "name": "Meera Nair",
        "role": "Police Officer",
        "password_env": "OFFICER_KL_PO_2275_PASSWORD",
    },
    "KL-HP-3318": {
        "name": "Arun Thomas",
        "role": "Helper",
        "password_env": "OFFICER_KL_HP_3318_PASSWORD",
    },
    "KL-HP-4402": {
        "name": "Sneha Varghese",
        "role": "Helper",
        "password_env": "OFFICER_KL_HP_4402_PASSWORD",
    },
}

SESSION_SECRET = os.getenv("OFFICER_SESSION_SECRET", "")


def encode_part(data):
    raw = json.dumps(data, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def issue_token(badge):
    payload = {
        "badge": badge,
        "exp": int(time.time()) + 3600,
    }
    body = encode_part(payload)
    signature = hmac.new(
        SESSION_SECRET.encode(),
        body.encode(),
        hashlib.sha256,
    ).digest()
    sig = base64.urlsafe_b64encode(signature).rstrip(b"=").decode()
    return body + "." + sig


def verify_officer_token():
    if not SESSION_SECRET:
        return None

    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return None

    token = header.split(" ", 1)[1]
    try:
        body, supplied_sig = token.split(".", 1)
        expected_sig = base64.urlsafe_b64encode(
            hmac.new(
                SESSION_SECRET.encode(),
                body.encode(),
                hashlib.sha256,
            ).digest()
        ).rstrip(b"=").decode()

        if not hmac.compare_digest(supplied_sig, expected_sig):
            return None

        padded = body + "=" * (-len(body) % 4)
        payload = json.loads(base64.urlsafe_b64decode(padded))

        if payload.get("exp", 0) < int(time.time()):
            return None

        badge = payload.get("badge")
        if badge not in OFFICERS:
            return None

        return badge
    except Exception:
        return None


@app.get("/")
def health_check():
    return jsonify({
        "status": "online",
        "service": "Guardian Alert Nearby Emergency Backend",
    }), 200


@app.post("/nearby-emergency-alert")
def nearby_alert():
    return nearby_emergency_alert(request)


@app.post("/register-emergency-alert")
def register_emergency_alert():
    return register_pending_emergency(request)

@app.post("/internal/process-overdue-alerts")
def process_overdue_alerts():
    expected_secret = os.getenv("EMERGENCY_WORKER_SECRET", "")
    supplied_secret = request.headers.get("X-Worker-Secret", "")

    if not expected_secret:
        return jsonify({"error": "Worker secret is not configured"}), 503

    if not hmac.compare_digest(supplied_secret, expected_secret):
        return jsonify({"error": "Unauthorized"}), 401

    try:
        count = process_overdue_pending_alerts()

        app.logger.info(
            "Overdue emergency check completed; escalated=%s",
            count,
        )

        return jsonify({
            "success": True,
            "escalated": count,
        }), 200

    except Exception:
        app.logger.exception("Overdue emergency processing failed")
        return jsonify({"error": "Emergency processing failed"}), 500

@app.get("/nearby-emergency-details")
def nearby_alert_details():
    return nearby_emergency_details(request)


@app.post("/officer-login")
def officer_login():
    if not SESSION_SECRET:
        return jsonify({"error": "Officer authentication is not configured"}), 503

    data = request.get_json(silent=True) or {}
    badge = str(data.get("badge", "")).strip().upper()
    password = str(data.get("password", ""))

    officer = OFFICERS.get(badge)
    expected_password = (
        os.getenv(officer["password_env"], "") if officer else ""
    )

    if (
        not officer
        or not expected_password
        or not hmac.compare_digest(password, expected_password)
    ):
        return jsonify({"error": "Invalid badge or password"}), 401

    return jsonify({
        "token": issue_token(badge),
        "badge": badge,
        "name": officer["name"],
        "role": officer["role"],
        "expiresIn": 3600,
    }), 200


@app.get("/officer-alerts")
def officer_alerts():
    badge = verify_officer_token()
    if not badge:
        return jsonify({"error": "Officer authentication required"}), 401

    try:
        alerts = []

        for snap in db.collection("emergency_alerts").stream():
            data = snap.to_dict() or {}

            if data.get("status") != "triggered":
                continue

            user_id = data.get("userId", "")
            profile = {}

            if user_id:
                profile_snap = db.collection("users").document(user_id).get()
                if profile_snap.exists:
                    profile = profile_snap.to_dict() or {}

            alerts.append({
                "id": snap.id,
                "userId": user_id,
                "name": data.get("userName") or data.get("name") or profile.get("name", ""),
                "phone": profile.get("phone", ""),
                "aboutMe": profile.get("aboutMe", ""),
                "latitude": data.get("latitude"),
                "longitude": data.get("longitude"),
                "alertType": data.get("alertType", "Emergency"),
                "createdAt": (
                    data["createdAt"].isoformat()
                    if hasattr(data.get("createdAt"), "isoformat")
                    else None
                ),
                "status": data.get("status"),
                "resolved": data.get("resolved", False),
                "resolvedBy": data.get("resolvedBy", ""),
            })

        return jsonify({"alerts": alerts}), 200

    except Exception as error:
        app.logger.exception("Could not fetch officer alerts")
        return jsonify({"error": "Could not fetch alerts"}), 500


@app.post("/officer-alerts/<alert_id>/resolve")
def resolve_alert(alert_id):
    badge = verify_officer_token()
    if not badge:
        return jsonify({"error": "Officer authentication required"}), 401

    try:
        ref = db.collection("emergency_alerts").document(alert_id)
        snap = ref.get()

        if not snap.exists:
            return jsonify({"error": "Alert not found"}), 404

        data = snap.to_dict() or {}
        if data.get("status") != "triggered":
            return jsonify({"error": "Alert is not triggered"}), 409

        body = request.get_json(silent=True) or {}
        resolved = body.get("resolved", True)

        if not isinstance(resolved, bool):
            return jsonify({"error": "resolved must be true or false"}), 400

        ref.update({
            "resolved": resolved,
            "resolvedBy": badge if resolved else "",
            "resolvedAt": (
                __import__("datetime").datetime.now(
                    __import__("datetime").timezone.utc
                ) if resolved else None
            ),
        })

        return jsonify({"success": True, "resolved": resolved}), 200

    except Exception:
        app.logger.exception("Could not update alert status")
        return jsonify({"error": "Could not update alert status"}), 500
