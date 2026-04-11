"""
APScheduler-backed reminder job manager.

Each Firestore reminder document maps to one APScheduler job, keyed by
`reminderId`. The job fires `send_reminder_push` at the scheduled time(s)
and pushes a notification through the Firebase Admin SDK.

The scheduler is in-memory by default — Render's free tier does not give us
durable disk between restarts, so jobs are re-hydrated by the Flutter client
the next time it calls `/reminders/schedule` after a backend redeploy.
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta
from typing import Optional

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.date import DateTrigger
from apscheduler.triggers.interval import IntervalTrigger

from . import fcm

logger = logging.getLogger(__name__)

# ── Repeat → APScheduler trigger mapping ─────────────────────────────

_INTERVAL_MAP = {
    "daily": timedelta(days=1),
    "every_2_days": timedelta(days=2),
    "weekly": timedelta(weeks=1),
    "biweekly": timedelta(weeks=2),
    # APScheduler IntervalTrigger has no "month" unit; we approximate as 30d.
    # For exact monthly recurrence the Flutter client also schedules a local
    # OS notification fallback.
    "monthly": timedelta(days=30),
}


# ── Module-level scheduler instance ──────────────────────────────────

scheduler: Optional[AsyncIOScheduler] = None


def start_scheduler() -> AsyncIOScheduler:
    """Create and start the global AsyncIOScheduler. Idempotent."""
    global scheduler
    if scheduler is not None and scheduler.running:
        return scheduler
    scheduler = AsyncIOScheduler()
    scheduler.start()
    logger.info("APScheduler started for reminder notifications.")
    return scheduler


def shutdown_scheduler() -> None:
    """Stop the global scheduler if it is running."""
    global scheduler
    if scheduler is not None and scheduler.running:
        scheduler.shutdown(wait=False)
        scheduler = None


# ── Job CRUD ─────────────────────────────────────────────────────────


def _parse_first_run(start_date: str, notify_time: str) -> datetime:
    """
    Combine an ISO date (YYYY-MM-DD) and HH:MM time string into a naive
    datetime in the server's local timezone (Render runs UTC).
    """
    year, month, day = (int(p) for p in start_date.split("-"))
    hour, minute = (int(p) for p in notify_time.split(":"))
    return datetime(year, month, day, hour, minute)


def schedule_reminder_job(
    *,
    reminder_id: str,
    uid: str,
    fcm_token: str,
    category: str,
    plant_name: str,
    repeat: str,
    start_date: str,
    notify_time: str,
    water_amount: Optional[str] = None,
) -> bool:
    """
    Schedule (or replace) the APScheduler job for a reminder.
    Returns True on success.
    """
    sched = start_scheduler()
    cancel_reminder_job(reminder_id)

    first_run = _parse_first_run(start_date, notify_time)
    now = datetime.now()

    title = f"{category.replace('_', ' ').capitalize()} Reminder"
    if category == "watering" and water_amount:
        body = f"Time to water your {plant_name} ({water_amount})"
    else:
        body = f"Time to {category.replace('_', ' ')} your {plant_name}"
    payload = {
        "reminderId": reminder_id,
        "uid": uid,
        "category": category,
    }

    job_kwargs = dict(
        func=send_reminder_push,
        kwargs={
            "fcm_token": fcm_token,
            "title": title,
            "body": body,
            "data": payload,
            "reminder_id": reminder_id,
        },
        id=reminder_id,
        replace_existing=True,
        misfire_grace_time=3600,
    )

    if repeat == "never":
        # If the date is already past, schedule it for one minute from now so
        # the user still gets the notification (mirrors mobile-OS behavior).
        run_at = first_run if first_run > now else now + timedelta(minutes=1)
        sched.add_job(trigger=DateTrigger(run_date=run_at), **job_kwargs)
    elif repeat in _INTERVAL_MAP:
        interval = _INTERVAL_MAP[repeat]
        # Walk forward to the next future occurrence.
        next_run = first_run
        while next_run <= now:
            next_run += interval
        sched.add_job(
            trigger=IntervalTrigger(
                seconds=int(interval.total_seconds()),
                start_date=next_run,
            ),
            **job_kwargs,
        )
    else:
        logger.warning("Unknown repeat value '%s' — defaulting to one-shot.", repeat)
        run_at = first_run if first_run > now else now + timedelta(minutes=1)
        sched.add_job(trigger=DateTrigger(run_date=run_at), **job_kwargs)

    logger.info(
        "Scheduled reminder job %s (%s, repeat=%s)",
        reminder_id,
        category,
        repeat,
    )
    return True


def cancel_reminder_job(reminder_id: str) -> bool:
    """Remove an existing job by reminder ID. Returns True if a job was removed."""
    sched = start_scheduler()
    try:
        sched.remove_job(reminder_id)
        logger.info("Cancelled reminder job %s", reminder_id)
        return True
    except Exception:
        return False


# ── Job execution ────────────────────────────────────────────────────


def send_reminder_push(
    *,
    fcm_token: str,
    title: str,
    body: str,
    data: dict,
    reminder_id: str,
) -> None:
    """
    APScheduler job target. Sends an FCM push notification.

    Note: Updating Firestore `isExpired` after delivery would require an
    Admin-SDK Firestore client; this is best left to the Flutter client which
    already observes the reminder document and can mark it expired locally
    once the scheduled time has passed.
    """
    delivered = fcm.send_push(
        fcm_token=fcm_token,
        title=title,
        body=body,
        data=data,
    )
    if not delivered:
        logger.warning("FCM push for reminder %s was not delivered.", reminder_id)
