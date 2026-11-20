from flask import jsonify
from firebase_admin import initialize_app, auth, firestore, credentials
from firebase_admin import messaging
from datetime import datetime, timezone, timedelta

import json
import math
import os

service_account_json = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")

if service_account_json:
    credential = credentials.Certificate(json.loads(service_account_json))
    initialize_app(credential)
else:
    initialize_app()

db = firestore.client()


def register_pending_emergency(req):
    """Register an owned pending Firestore alert for server-side escalation."""
    if req.method != "POST":
        return jsonify({"error": "POST method required"}), 405

    authorization = req.headers.get("Authorization", "")
    if not authorization.startswith("Bearer "):
        return jsonify({"error": "Missing Firebase ID token"}), 401

    try:
        decoded = auth.verify_id_token(authorization.split(" ", 1)[1])
    except Exception:
        return jsonify({"error": "Invalid or expired Firebase ID token"}), 401

    data = req.get_json(silent=True) or {}
    alert_id = data.get("alertId")
    if not isinstance(alert_id, str) or not alert_id.strip():
        return jsonify({"error": "A valid alertId is required"}), 400

    ref = db.collection("emergency_alerts").document(alert_id.strip())
    transaction = db.transaction()
    now = datetime.now(timezone.utc)

    @firestore.transactional
    def register(tx):
        snap = ref.get(transaction=tx)
        if not snap.exists:
            return "not_found"
        alert = snap.to_dict() or {}
        if alert.get("userId") != decoded["uid"]:
            return "unauthorized"
        if alert.get("status") != "pending":
            return "not_pending"

        # Idempotent registration: don't extend an already-created deadline.
        if alert.get("serverExpiresAt") is not None:
            return "registered"

        tx.update(ref, {
            "serverTimerRegisteredAt": firestore.SERVER_TIMESTAMP,
            "serverExpiresAt": now + timedelta(seconds=30),
            "serverTimerVersion": 1,
        })
        return "registered"

    try:
        result = register(transaction)
    except Exception:
        return jsonify({"error": "Could not register server timer"}), 500

    if result == "not_found":
        return jsonify({"error": "Alert not found"}), 404
    if result == "unauthorized":
        return jsonify({"error": "Alert does not belong to this user"}), 403
    if result == "not_pending":
        return jsonify({"error": "Alert is no longer pending"}), 409

    snap = ref.get()
    expiry = (snap.to_dict() or {}).get("serverExpiresAt")
    return jsonify({
        "success": True,
        "alertId": alert_id,
        "status": "pending",
        "expiresAt": expiry.isoformat() if hasattr(expiry, "isoformat") else None,
        "countdownSeconds": 30,
    }), 200


def _dispatch_escalated_alert(alert_id: str, alert: dict) -> None:
    """Send nearby FCM notifications for an alert escalated by the worker."""
    latitude = alert.get("latitude")
    longitude = alert.get("longitude")
    caller_uid = alert.get("userId")
    if not caller_uid or not is_valid_coordinates(latitude, longitude):
        print(f"WORKER: Alert {alert_id} escalated without valid owner/location; skipping nearby FCM")
        return

    recipients = get_nearby_recipients(latitude, longitude, caller_uid)
    user_name = alert.get("userName") or alert.get("name") or "A nearby user"
    for recipient_uid in recipients:
        if not claim_notification_delivery(alert_id, recipient_uid):
            continue
        token = get_recipient_fcm_token(recipient_uid)
        if not token:
            try:
                update_notification_delivery(alert_id, recipient_uid, "failed", "No valid FCM token registered")
            except Exception as error:
                print(f"WORKER: Could not record missing token for {alert_id}: {error}")
            continue
        try:
            success = send_nearby_alert_notification(token, alert_id, user_name, latitude, longitude)
        except Exception as error:
            print(f"WORKER: FCM send failed for alert {alert_id}: {error}")
            success = False
        try:
            update_notification_delivery(
                alert_id, recipient_uid,
                "sent" if success else "failed",
                "" if success else "FCM send failed",
            )
        except Exception as error:
            print(f"WORKER: Could not record delivery for alert {alert_id}: {error}")


def process_overdue_pending_alerts() -> int:
    """Atomically escalate overdue registered alerts and dispatch notifications."""
    now = datetime.now(timezone.utc)
    query = (
        db.collection("emergency_alerts")
        .where("status", "==", "pending")
        .where("serverExpiresAt", "<=", now)
        .limit(100)
    )
    escalated_count = 0

    for candidate in query.stream():
        ref = db.collection("emergency_alerts").document(candidate.id)
        transaction = db.transaction()

        @firestore.transactional
        def escalate(tx):
            snap = ref.get(transaction=tx)
            if not snap.exists:
                return None
            alert = snap.to_dict() or {}
            expires = alert.get("serverExpiresAt")
            current_now = datetime.now(timezone.utc)
            if alert.get("status") != "pending" or not isinstance(expires, datetime):
                return None
            if expires.tzinfo is None:
                expires = expires.replace(tzinfo=timezone.utc)
            if expires > current_now:
                return None
            tx.update(ref, {
                "status": "triggered",
                "escalatedAt": firestore.SERVER_TIMESTAMP,
                "escalationReason": "No cancellation received before server deadline",
                "updatedAt": firestore.SERVER_TIMESTAMP,
            })
            return alert

        try:
            prior_alert = escalate(transaction)
        except Exception as error:
            print(f"WORKER: Failed to escalate {candidate.id}: {error}")
            continue

        if prior_alert is None:
            continue

        escalated_count += 1
        print(f"WORKER: Escalated overdue alert {candidate.id}")
        # Dispatch only after the transaction commits. Delivery records prevent
        # the app endpoint and worker from sending duplicate notifications.
        try:
            _dispatch_escalated_alert(candidate.id, prior_alert)
        except Exception as error:
            print(f"WORKER: Notification dispatch failed for {candidate.id}: {error}")

    return escalated_count


def verify_authenticated_user(req):
    # Allow POST requests only.
    if req.method != "POST":
        return jsonify({"error": "POST method required"}), 405

    # Read the Firebase ID token from the Authorization header.
    authorization = req.headers.get("Authorization", "")
    if not authorization.startswith("Bearer "):
        return jsonify({"error": "Missing Firebase ID token"}), 401

    id_token = authorization.split(" ", 1)[1]

    try:
        decoded_token = auth.verify_id_token(id_token)
    except Exception:
        return jsonify({"error": "Invalid or expired Firebase ID token"}), 401

    return jsonify({
            "success": True,
            "uid": decoded_token["uid"],
            "message": "Firebase authentication verified",
        }), 200


def nearby_emergency_alert(req):
    if req.method != "POST":
        return jsonify({"error": "POST method required"}), 405

    authorization = req.headers.get("Authorization", "")
    if not authorization.startswith("Bearer "):
        return jsonify({"error": "Missing Firebase ID token"}), 401

    try:
        decoded_token = auth.verify_id_token(
            authorization.split(" ", 1)[1]
        )
    except Exception:
        return jsonify({"error": "Invalid or expired Firebase ID token"}), 401

    caller_uid = decoded_token["uid"]

    try:
        request_data = req.get_json(silent=True) or {}
        alert_id = request_data.get("alertId")

        if not isinstance(alert_id, str) or not alert_id.strip():
            return jsonify({"error": "A valid alertId is required"}), 400

        alert = get_valid_triggered_alert(alert_id, caller_uid)

        if alert is None:
            return jsonify({
                    "error": "Alert not found, not triggered, or unauthorized"
                }), 404

        latitude = alert["latitude"]
        longitude = alert["longitude"]
        user_name = alert.get("userName", "A nearby user")

        recipient_uids = get_nearby_recipients(
            latitude,
            longitude,
            caller_uid,
        )

        sent_count = 0
        failed_count = 0

        for recipient_uid in recipient_uids:
            token = get_recipient_fcm_token(recipient_uid)

            if not token:
                if claim_notification_delivery(alert_id, recipient_uid):
                    try:
                        update_notification_delivery(
                            alert_id,
                            recipient_uid,
                            "failed",
                            "No valid FCM token registered",
                        )
                    except Exception as error:
                        print(
                            f"Could not record missing-token delivery for "
                            f"alert {alert_id}: {error}"
                        )
                continue

            if not claim_notification_delivery(
                alert_id,
                recipient_uid,
            ):
                continue

            try:
                success = send_nearby_alert_notification(
                    token,
                    alert_id,
                    user_name,
                    latitude,
                    longitude,
                )
            except Exception as error:
                success = False
                print(f"Notification error: {error}")

            if success:
                try:
                    update_notification_delivery(
                        alert_id,
                        recipient_uid,
                        "sent",
                    )
                    sent_count += 1
                except Exception as error:
                # FCM may already have accepted the notification.
                # Do not mark it failed or automatically retry it.
                    print(
                        "FCM accepted the notification, but recording "
                        f"delivery status failed for alert {alert_id}: {error}"
                    )
                    failed_count += 1
            else:
                try:
                    update_notification_delivery(
                        alert_id,
                        recipient_uid,
                        "failed",
                        "FCM send failed",
                    )
                except Exception as error:
                    print(
                        f"Could not record failed delivery for alert "
                        f"{alert_id}: {error}"
                    )
                    failed_count += 1

        return jsonify({
                "success": True,
                "message": "Nearby alert processing completed",
                "recipientsFound": len(recipient_uids),
                "notificationsSent": sent_count,
                "notificationsFailed": failed_count,
            }), 200

    except Exception as error:
        print(f"Nearby alert processing failed: {error}")
        return jsonify({"error": "Nearby alert processing failed"}), 500


def nearby_emergency_details(req):
    authorization = req.headers.get("Authorization", "")

    if not authorization.startswith("Bearer "):
        return jsonify({"error": "Missing Firebase ID token"}), 401

    try:
        decoded_token = auth.verify_id_token(
            authorization.split(" ", 1)[1]
        )
    except Exception:
        return jsonify({"error": "Invalid or expired Firebase ID token"}), 401

    recipient_uid = decoded_token["uid"]
    alert_id = req.args.get("alertId", "").strip()

    if not alert_id:
        return jsonify({"error": "A valid alertId is required"}), 400

    try:
        alert_ref = db.collection("emergency_alerts").document(alert_id)
        delivery_ref = (
            alert_ref.collection("notification_deliveries")
            .document(recipient_uid)
        )

        delivery = delivery_ref.get()

        if not delivery.exists:
            return jsonify({"error": "Not authorized to view this alert"}), 403

        delivery_data = delivery.to_dict() or {}

        if delivery_data.get("status") != "sent":
            return jsonify({"error": "Not authorized to view this alert"}), 403

        alert_snapshot = alert_ref.get()

        if not alert_snapshot.exists:
            return jsonify({"error": "Alert not found"}), 404

        alert = alert_snapshot.to_dict() or {}

        if alert.get("status") != "triggered":
            return jsonify({"error": "Alert is no longer active"}), 404

        return jsonify({
            "success": True,
            "alert": {
                "alertId": alert_id,
                "userName": alert.get("userName", "Unknown user"),
                "latitude": alert.get("latitude"),
                "longitude": alert.get("longitude"),
                "status": alert.get("status"),
                "createdAt": (
                    alert["createdAt"].isoformat()
                    if hasattr(alert.get("createdAt"), "isoformat")
                    else None
                ),
            },
        }), 200

    except Exception as error:
        print(f"Could not retrieve emergency details: {error}")
        return jsonify({"error": "Could not retrieve emergency details"}), 500


def calculate_distance_km(
    lat1: float,
    lon1: float,
    lat2: float,
    lon2: float,
) -> float:
    """Calculate the distance between two coordinates in kilometres."""
    earth_radius_km = 6371.0

    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    delta_lat = math.radians(lat2 - lat1)
    delta_lon = math.radians(lon2 - lon1)

    a = (
        math.sin(delta_lat / 2) ** 2
        + math.cos(lat1_rad)
        * math.cos(lat2_rad)
        * math.sin(delta_lon / 2) ** 2
    )

    a = max(0.0, min(1.0, a))
    central_angle = 2 * math.atan2(
        math.sqrt(a),
        math.sqrt(1.0 - a),
    )

    return earth_radius_km * central_angle

from datetime import datetime, timezone, timedelta


NEARBY_RADIUS_KM = 5.0
MAX_LOCATION_AGE = timedelta(minutes=60)


def is_valid_coordinates(latitude, longitude) -> bool:
    """Check whether coordinates are valid numeric latitude/longitude."""
    if (
        isinstance(latitude, bool)
        or isinstance(longitude, bool)
        or not isinstance(latitude, (int, float))
        or not isinstance(longitude, (int, float))
    ):
        return False

    return (
        math.isfinite(latitude)
        and math.isfinite(longitude)
        and -90 <= latitude <= 90
        and -180 <= longitude <= 180
    )


def is_location_fresh(updated_at, now=None) -> bool:
    """Accept only Firestore timestamps from the last 60 minutes."""
    if not isinstance(updated_at, datetime):
        return False

    now = now or datetime.now(timezone.utc)

    if updated_at.tzinfo is None:
        updated_at = updated_at.replace(tzinfo=timezone.utc)

    age = now - updated_at.astimezone(timezone.utc)

    return timedelta(0) <= age <= MAX_LOCATION_AGE

def get_valid_triggered_alert(alert_id: str, caller_uid: str):
    """Return a valid triggered alert owned by the authenticated caller."""
    if not isinstance(alert_id, str) or not alert_id.strip():
        return None

    document = db.collection("emergency_alerts").document(alert_id).get()

    if not document.exists:
        return None

    alert = document.to_dict() or {}

    if alert.get("userId") != caller_uid:
        return None

    if alert.get("status") != "triggered":
        return None

    latitude = alert.get("latitude")
    longitude = alert.get("longitude")

    if not is_valid_coordinates(latitude, longitude):
        return None

    return alert

def get_nearby_recipients(
    alert_latitude: float,
    alert_longitude: float,
    caller_uid: str,
) -> list:
    """Find opted-in users with fresh locations within 5 km."""
    recipients = []
    now = datetime.now(timezone.utc)

    locations = db.collection("user_locations").stream()

    for document in locations:
        user_uid = document.id

        # Do not notify the person who triggered the alert.
        if user_uid == caller_uid:
            continue

        location = document.to_dict() or {}

        # Only include users who explicitly opted in.
        if location.get("nearbyAlertsEnabled") is not True:
            continue

        latitude = location.get("latitude")
        longitude = location.get("longitude")
        updated_at = location.get("updatedAt")

        if not is_valid_coordinates(latitude, longitude):
            continue

        if not is_location_fresh(updated_at, now):
            continue

        distance = calculate_distance_km(
            alert_latitude,
            alert_longitude,
            latitude,
            longitude,
        )

        if distance <= NEARBY_RADIUS_KM:
            recipients.append(user_uid)

    return recipients

def get_recipient_fcm_token(user_uid: str):
    """Retrieve an opted-in recipient's registered FCM token."""
    document = (
        db.collection("fcm_tokens")
        .document(user_uid)
        .get()
    )

    if not document.exists:
        return None

    token_data = document.to_dict() or {}

    if token_data.get("uid") != user_uid:
        return None

    token = token_data.get("token")

    if not isinstance(token, str) or not token.strip():
        return None

    return token


def send_nearby_alert_notification(
    token: str,
    alert_id: str,
    user_name: str,
    latitude: float,
    longitude: float,
) -> bool:
    """Send an emergency notification with the user's name and location."""

    location_text = f"{latitude:.5f}, {longitude:.5f}"

    message = messaging.Message(
        notification=messaging.Notification(
            title="Nearby Emergency Alert",
            body=(
                f"{user_name} may need emergency assistance. "
                f"Location: {location_text}"
            ),
        ),
        data={
            "type": "nearby_emergency",
            "alertId": alert_id,
            "userName": user_name,
            "latitude": str(latitude),
            "longitude": str(longitude),
        },
        token=token,
    )

    try:
        messaging.send(message)
        return True
    except Exception as error:
        print(f"FCM notification failed: {error}")
        return False


def claim_notification_delivery(
    alert_id: str,
    recipient_uid: str,
) -> bool:
    """Claim a notification delivery, allowing safe retries after failure."""
    delivery_ref = (
        db.collection("emergency_alerts")
        .document(alert_id)
        .collection("notification_deliveries")
        .document(recipient_uid)
    )

    transaction = db.transaction()

    @firestore.transactional
    def claim_in_transaction(transaction):
        snapshot = delivery_ref.get(transaction=transaction)

        if snapshot.exists:
            data = snapshot.to_dict() or {}
            status = data.get("status")

            # Never resend a notification already accepted by FCM.
            if status == "sent":
                return False

            # Avoid duplicate concurrent attempts.
            if status == "processing":
                return False

            # Failed deliveries can be retried.
            if status != "failed":
                return False

            transaction.update(delivery_ref, {
                "status": "processing",
                "createdAt": firestore.SERVER_TIMESTAMP,
                "completedAt": firestore.DELETE_FIELD,
                "error": "",
            })
        else:
            transaction.create(delivery_ref, {
                "recipientUid": recipient_uid,
                "status": "processing",
                "createdAt": firestore.SERVER_TIMESTAMP,
            })

        return True

    try:
        return claim_in_transaction(transaction)
    except Exception as error:
        print(f"Could not claim notification delivery: {error}")
        return False

def update_notification_delivery(
    alert_id: str,
    recipient_uid: str,
    status: str,
    error_message: str = "",
) -> None:
    """Record the outcome of a notification delivery attempt."""
    if status not in ("sent", "failed"):
        raise ValueError("Invalid notification delivery status")

    delivery_ref = (
        db.collection("emergency_alerts")
        .document(alert_id)
        .collection("notification_deliveries")
        .document(recipient_uid)
    )

    delivery_ref.update({
        "status": status,
        "completedAt": firestore.SERVER_TIMESTAMP,
        "error": error_message[:500] if error_message else "",
    })