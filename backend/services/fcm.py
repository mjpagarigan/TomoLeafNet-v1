"""
Firebase Admin SDK initialization and FCM push delivery helper.

The service-account JSON is read from the FIREBASE_SERVICE_ACCOUNT_JSON
environment variable on Render. For local development you can set the same
variable in `.env`. Never commit the JSON file to the repository.
"""
from __future__ import annotations

import json
import logging
import os
from typing import Optional

logger = logging.getLogger(__name__)

_initialized = False
_admin_messaging = None  # firebase_admin.messaging module, lazy-loaded


def init_firebase_admin() -> bool:
    """Initialize the Firebase Admin SDK once. Returns True on success."""
    global _initialized, _admin_messaging
    if _initialized:
        return True

    raw = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON")
    if not raw:
        logger.warning(
            "FIREBASE_SERVICE_ACCOUNT_JSON not set — FCM push delivery disabled."
        )
        return False

    try:
        import firebase_admin  # type: ignore
        from firebase_admin import credentials, messaging  # type: ignore

        # The env var may be a JSON blob or a path to a JSON file.
        if raw.strip().startswith("{"):
            cred = credentials.Certificate(json.loads(raw))
        else:
            cred = credentials.Certificate(raw)

        if not firebase_admin._apps:
            firebase_admin.initialize_app(cred)

        _admin_messaging = messaging
        _initialized = True
        logger.info("Firebase Admin SDK initialized.")
        return True
    except Exception as exc:  # pragma: no cover - depends on env
        logger.exception("Failed to initialize Firebase Admin SDK: %s", exc)
        return False


def send_push(
    *,
    fcm_token: str,
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> bool:
    """
    Send a single FCM push to the given device token. Returns True on success.
    Quietly no-ops if the Admin SDK is not initialized.
    """
    if not _initialized and not init_firebase_admin():
        return False
    if _admin_messaging is None:
        return False

    try:
        message = _admin_messaging.Message(
            notification=_admin_messaging.Notification(title=title, body=body),
            token=fcm_token,
            data={k: str(v) for k, v in (data or {}).items()},
        )
        message_id = _admin_messaging.send(message)
        logger.info("FCM push sent: %s", message_id)
        return True
    except Exception as exc:
        logger.exception("FCM push delivery failed: %s", exc)
        return False
