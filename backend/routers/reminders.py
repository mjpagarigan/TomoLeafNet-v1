"""
Reminder scheduling endpoints.

These are called by the Flutter client whenever the user creates, edits, or
deletes a reminder. Each request manipulates an in-memory APScheduler job
that fires an FCM push notification at the scheduled time(s).
"""
from __future__ import annotations

from datetime import datetime
from typing import Optional

from fastapi import APIRouter, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from services import scheduler as scheduler_svc

router = APIRouter(prefix="/reminders", tags=["reminders"])


class ScheduleRequest(BaseModel):
    reminderId: str
    uid: str
    fcmToken: str
    category: str
    plantName: str
    repeat: str
    startDate: str  # YYYY-MM-DD
    notifyTime: str  # HH:MM (24h)
    waterAmount: Optional[str] = None


class CancelRequest(BaseModel):
    reminderId: str
    uid: str


class GenericResponse(BaseModel):
    ok: bool
    detail: str = ""


def _validate_not_in_past(req: ScheduleRequest):
    """Return a 400 JSONResponse if the computed start + notify is in the past."""
    try:
        year, month, day = (int(p) for p in req.startDate.split("-"))
        hour, minute = (int(p) for p in req.notifyTime.split(":"))
        scheduled = datetime(year, month, day, hour, minute)
        if scheduled < datetime.now():
            return JSONResponse(
                status_code=400,
                content={
                    "error": "Cannot schedule a reminder in the past.",
                    "code": 400,
                },
            )
    except (ValueError, IndexError):
        pass
    return None


@router.post("/schedule", response_model=GenericResponse)
async def schedule_reminder(req: ScheduleRequest):
    rejection = _validate_not_in_past(req)
    if rejection is not None:
        return rejection

    try:
        scheduler_svc.schedule_reminder_job(
            reminder_id=req.reminderId,
            uid=req.uid,
            fcm_token=req.fcmToken,
            category=req.category,
            plant_name=req.plantName,
            repeat=req.repeat,
            start_date=req.startDate,
            notify_time=req.notifyTime,
            water_amount=req.waterAmount,
        )
        return GenericResponse(ok=True, detail="scheduled")
    except Exception as exc:  # pragma: no cover - defensive
        raise HTTPException(status_code=500, detail=f"schedule failed: {exc}")


@router.post("/update", response_model=GenericResponse)
async def update_reminder(req: ScheduleRequest):
    rejection = _validate_not_in_past(req)
    if rejection is not None:
        return rejection

    try:
        scheduler_svc.cancel_reminder_job(req.reminderId)
        scheduler_svc.schedule_reminder_job(
            reminder_id=req.reminderId,
            uid=req.uid,
            fcm_token=req.fcmToken,
            category=req.category,
            plant_name=req.plantName,
            repeat=req.repeat,
            start_date=req.startDate,
            notify_time=req.notifyTime,
            water_amount=req.waterAmount,
        )
        return GenericResponse(ok=True, detail="updated")
    except Exception as exc:  # pragma: no cover - defensive
        raise HTTPException(status_code=500, detail=f"update failed: {exc}")


@router.post("/cancel", response_model=GenericResponse)
async def cancel_reminder(req: CancelRequest) -> GenericResponse:
    removed = scheduler_svc.cancel_reminder_job(req.reminderId)
    return GenericResponse(
        ok=True,
        detail="cancelled" if removed else "no job found",
    )
