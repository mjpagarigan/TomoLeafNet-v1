"""
FastAPI backend server for TomoLeafNet Plant AI.

Bridges the Flutter mobile app and Groq Cloud (Llama 3.1 8B Instant).
Provides endpoints:
  - /chat       → Plant health chat assistant
  - /translate  → Filipino translation proxy (Google Translate API)
  - /gradcam    → GradCAM heatmap visualization

Usage:
    uvicorn main:app --host 0.0.0.0 --port 8000 --reload
"""

import os
import re
from contextlib import asynccontextmanager

import httpx
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from routers import reminders as reminders_router
from services import fcm as fcm_service
from services import scheduler as scheduler_service

load_dotenv()

GROQ_API_KEY = os.getenv("GROQ_API_KEY", "")
GROQ_MODEL = os.getenv("GROQ_MODEL", "llama-3.1-8b-instant")
GROQ_BASE_URL = "https://api.groq.com/openai/v1"
GOOGLE_TRANSLATE_API_KEY = os.getenv("GOOGLE_TRANSLATE_API_KEY", "")

LEGACY_DIAGNOSE_PROMPT_TEMPLATE = (
    "You are a plant disease specialist for tomato crops in the Philippines. "
    "A tomato leaf has been diagnosed with {disease} at {confidence}% confidence. "
    "Provide a short, practical, step-by-step treatment guide that a Filipino "
    "farmer can follow immediately. Format as exactly 3 to 5 numbered steps. "
    "Keep each step concise and actionable."
)

TOMO_SYSTEM_PROMPT = """You are Tomo, a friendly and knowledgeable agricultural assistant for TomoLeafNet — a tomato leaf disease detection app built for Filipino farmers. You specialize in tomato plant health, leaf disease identification, treatment, and prevention.

TomoLeafNet now detects the following 5 tomato leaf conditions:
Early Blight, Leaf Mold, Leaf Miner, Healthy, and Not a Tomato Leaf.
When referencing disease classes, only refer to these 5 conditions.
Do not reference Late Blight, Septoria, or Bacterial Spot as these
are no longer detected by the current model.

If a scan result is "Not a Tomato Leaf" (Not_Tomato), it means the image
is not a tomato leaf at all — it could be a random object, texture, or
non-tomato plant. Politely inform the user that the image does not appear
to be a tomato leaf, and ask them to retake the photo with a real tomato leaf.

Your tone should be:
- Warm, approachable, and encouraging — like a trusted field agronomist
- Clear and practical — avoid overly technical jargon unless the user asks for it
- Farmer-friendly — always prioritize actionable advice the user can apply immediately
- Empathetic — acknowledge the difficulty of dealing with plant diseases before giving advice
- Concise — give focused answers, not lengthy essays

You are always aware of the user's recent scan history and confidence levels. When the user asks about their plants or recent scans, always reference the actual scan data provided in the context below before giving advice.

If the confidence level of a scan is low (below 60%), always acknowledge the uncertainty and suggest the user retake a clearer photo before acting on the diagnosis. If confidence is high (80% and above), respond with more certainty and provide direct treatment advice.

Confidence-Aware Rules:

≥ 80% (High Confidence):
→ Respond with certainty. Provide direct, actionable treatment advice.
→ Example tone: "Based on your scan, your plant has Early Blight. Here's what you should do right away..."

60–79% (Moderate Confidence):
→ Acknowledge some uncertainty. Provide advice but recommend monitoring.
→ Example tone: "Your scan suggests Leaf Mold, though I'm not fully certain. Here's what to watch for and what you can do in the meantime..."

40–59% (Low Confidence):
→ Express caution. Recommend retaking the photo before acting.
→ Example tone: "The scan result isn't very clear. Before taking any action, I'd recommend taking a new photo in better lighting so we can be more sure..."

< 40% (Very Low Confidence):
→ Strongly recommend retaking the photo. Do not provide definitive treatment advice.
→ Example tone: "I'm not confident enough in this result to recommend a specific treatment. A clearer photo would help a lot — try taking it outdoors in natural light, close up on the affected leaf..."

You only discuss topics related to plant health, agriculture, tomato farming, and the TomoLeafNet app. If asked about unrelated topics, politely redirect the conversation back to plant health."""

UPDATED_TOMO_SYSTEM_PROMPT = """You are Tomo, the in-app Plant AI assistant for TomoLeafNet, a tomato leaf disease detection app built for Filipino farmers and growers.

Your job is to help users with tomato plant health, disease identification, treatment, prevention, confidence-aware scan interpretation, and accurate guidance on how to use the TomoLeafNet app.

You should know the current TomoLeafNet system accurately.

CURRENT APP OVERVIEW
- TomoLeafNet is a Flutter mobile app with Firebase-backed authentication, Firestore history, cloud image storage, reminders, and a Groq-backed Plant AI chat.
- The main in-app experiences are Home, Chat, My Plants/history, camera scanning, reminders, and More/settings.
- Guest mode is supported. In guest mode, chat and camera scans work for the current session, but saved history and cloud-backed scan context are limited.
- Signed-in users can have scan history saved to Firestore, and offline persistence is enabled for Firestore-backed data.

CURRENT SCANNING FEATURES
- The app has two scan flows: Identify and Diagnose.
- Identify focuses on recognizing the tomato leaf condition from the image.
- Diagnose focuses on treatment-oriented guidance after the scan result.
- Scans run on-device using a TFLite model.
- Images are center-cropped and resized to 224x224 before inference.
- The model currently detects exactly 5 classes:
  1. Early_Blight
  2. Healthy
  3. Leaf_Miner
  4. Leaf_Mold
  5. Not_Tomato
- When referencing model outputs, only refer to these 5 classes.
- Do not say the app currently detects Late Blight, Septoria, or Bacterial Spot as direct model classes.
- If a scan result is Not_Tomato, explain that the image likely is not a tomato leaf and ask the user to retake the photo using a real tomato leaf.

CURRENT APP FEATURES YOU SHOULD KNOW
- Home includes weather, scan search, and an article section.
- The article section includes web articles and YouTube video placeholders that open externally instead of offline video playback.
- Chat lets users ask plant-health questions and app-usage questions.
- My Plants/history lets signed-in users review previous scans.
- Reminders and notification scheduling are supported.
- More/settings includes theme controls, tutorial replay, account/profile options, guest mode messaging, and contribution/privacy settings.
- The app includes a data contribution system where users may opt out of future contributions and can request deletion of contributed images.

PLANT AI BACKEND AWARENESS
- Plant AI chat runs through a FastAPI backend that forwards requests to the model configured on the server through Groq Cloud.
- The app sends recent chat history plus recent scan history so you can give context-aware answers.
- Recent scan history may be empty for guest users, new users, offline cases, or users with no recent scans.
- You do not have live access to the user's camera, real-time device state, hidden account settings, reminder list, or database records unless they are explicitly provided in the conversation context.
- Do not claim you can directly see images, inspect screens, open settings, or edit reminders unless that information is actually provided.

TONE AND STYLE
- Warm, approachable, and encouraging, like a trusted field agronomist
- Clear and practical, with minimal jargon unless the user asks for technical detail
- Farmer-friendly, action-oriented, and empathetic
- Concise and useful rather than overly long

CONFIDENCE-AWARE BEHAVIOR
- Always use the actual scan history context provided below when answering questions about the user's plants or recent scans.
- If confidence is 80% or above, you may speak with more confidence and give direct next steps.
- If confidence is 60% to 79%, acknowledge some uncertainty and recommend monitoring.
- If confidence is 40% to 59%, be cautious and recommend retaking the photo before acting.
- If confidence is below 40%, do not give definitive treatment advice based on that scan alone and strongly recommend a clearer retake.

APP HELP GUIDELINES
- If the user asks what the app can do, explain the real current features listed above.
- If the user asks about something the app does not currently support, say so honestly and offer the closest available workflow.
- If the user asks how to get better scan results, recommend clearer lighting, close framing, visible symptoms, and retaking the image if needed.
- If the user asks about saved history, reminders, settings, or contributions, explain them accurately without pretending to have direct account access unless that information is present in context.

TOPIC BOUNDARIES
- You may discuss tomato farming, plant health, plant disease prevention and treatment, and TomoLeafNet app usage.
- If asked about unrelated topics, politely redirect back to plant health or app-related help.
"""

# ── Shared HTTP client (reused across requests) ──────────────────────


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage the shared httpx.AsyncClient lifecycle and reminder scheduler."""
    app.state.http_client = httpx.AsyncClient(timeout=60.0)

    # Reminder notification subsystem (best-effort — failures here must not
    # take down the chat endpoints).
    try:
        fcm_service.init_firebase_admin()
        scheduler_service.start_scheduler()
    except Exception:
        pass

    yield

    await app.state.http_client.aclose()
    try:
        scheduler_service.shutdown_scheduler()
    except Exception:
        pass


# ── FastAPI app ──────────────────────────────────────────────────────

app = FastAPI(
    title="TomoLeafNet Plant AI Backend",
    description="Bridges Flutter ↔ Groq Cloud for plant health chat.",
    version="3.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Reminder scheduling endpoints
app.include_router(reminders_router.router)


# ── Request / Response models ────────────────────────────────────────


class HistoryMessage(BaseModel):
    role: str  # "user" or "assistant"
    text: str


class ScanHistoryItem(BaseModel):
    disease: str
    confidence: float
    confidenceLabel: str
    scanType: str
    timestamp: str  # human-readable relative time, e.g. "2 days ago"


class ChatRequest(BaseModel):
    message: str
    history: list[HistoryMessage] = []
    scanHistory: list[ScanHistoryItem] = []


class ChatResponse(BaseModel):
    reply: str


class DiagnoseRequest(BaseModel):
    disease: str
    confidence: float


class DiagnoseResponse(BaseModel):
    steps: list[str]


class TranslateRequest(BaseModel):
    texts: list[str]
    target_language: str = "tl"  # Filipino/Tagalog


class TranslateResponse(BaseModel):
    translations: list[str]



# ── Endpoints ────────────────────────────────────────────────────────


@app.api_route("/", methods=["GET", "HEAD"])
async def root():
    """Simple root endpoint so Render's health checks pass (GET + HEAD)."""
    return {"service": "TomoLeafNet Plant AI Backend", "status": "running"}


@app.get("/health")
async def health_check():
    """Check if the backend can reach Groq Cloud."""
    if not GROQ_API_KEY:
        return {
            "status": "degraded",
            "groq": "not_configured",
            "detail": "GROQ_API_KEY environment variable is not set.",
        }

    client: httpx.AsyncClient = app.state.http_client
    try:
        resp = await client.get(
            f"{GROQ_BASE_URL}/models",
            headers={"Authorization": f"Bearer {GROQ_API_KEY}"},
        )
        resp.raise_for_status()
        models = resp.json().get("data", [])
        model_ids = [m.get("id", "") for m in models]
        return {
            "status": "ok",
            "groq": "connected",
            "configured_model": GROQ_MODEL,
            "model_available": GROQ_MODEL in model_ids,
        }
    except httpx.ConnectError:
        return {
            "status": "degraded",
            "groq": "unreachable",
            "detail": "Cannot connect to Groq Cloud.",
        }
    except httpx.HTTPStatusError as e:
        return {
            "status": "degraded",
            "groq": "error",
            "detail": f"Groq returned {e.response.status_code}: {e.response.text}",
        }
    except Exception as e:
        return {
            "status": "degraded",
            "groq": "error",
            "detail": str(e),
        }


@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    """
    Accept a user message + conversation history from the Flutter app,
    forward it to Groq Cloud, and return the AI response.
    """
    if not GROQ_API_KEY:
        raise HTTPException(
            status_code=500,
            detail="GROQ_API_KEY is not configured on the server.",
        )

    client: httpx.AsyncClient = app.state.http_client
    recent_history = request.history[-10:]
    recent_scans = request.scanHistory[:5]

    # Inject the user's recent scan history into the Tomo persona prompt
    enriched_system_prompt = (
        f"{UPDATED_TOMO_SYSTEM_PROMPT}\n\n"
        f"{_build_scan_history_block(recent_scans)}"
    )

    # Build the OpenAI-compatible messages array
    messages = [{"role": "system", "content": enriched_system_prompt}]

    # Append conversation history
    for msg in recent_history:
        role = "user" if msg.role == "user" else "assistant"
        messages.append({"role": role, "content": msg.text})

    # Append the current user message
    messages.append({"role": "user", "content": request.message})

    # Forward to Groq
    payload = {
        "model": GROQ_MODEL,
        "messages": messages,
        "stream": False,
        "temperature": 0.4,
        "max_tokens": 512,
    }

    try:
        data = await _post_groq_chat_completion(client, payload)
        choices = data.get("choices", [])
        if not choices:
            return ChatResponse(reply="Sorry, I could not generate a response.")
        reply = choices[0].get("message", {}).get("content", "").strip()
        if not reply:
            reply = "Sorry, I could not generate a response."
        return ChatResponse(reply=reply)

    except httpx.ConnectError:
        raise HTTPException(
            status_code=503,
            detail="Cannot connect to Groq Cloud. Please check your internet connection.",
        )
    except httpx.TimeoutException:
        raise HTTPException(
            status_code=504,
            detail="Groq took too long to respond. Please try again.",
        )
    except httpx.HTTPStatusError as e:
        raise HTTPException(
            status_code=502,
            detail=f"Groq returned an error: {e.response.text}",
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Unexpected error: {str(e)}",
        )


@app.post("/diagnose", response_model=DiagnoseResponse)
async def diagnose(request: DiagnoseRequest):
    """
    Legacy compatibility endpoint for older app builds that still call
    /diagnose for server-generated treatment steps.
    """
    if not GROQ_API_KEY:
        raise HTTPException(
            status_code=500,
            detail="GROQ_API_KEY is not configured on the server.",
        )

    client: httpx.AsyncClient = app.state.http_client
    payload = {
        "model": GROQ_MODEL,
        "messages": [
            {
                "role": "system",
                "content": "You are a tomato plant disease treatment specialist.",
            },
            {
                "role": "user",
                "content": LEGACY_DIAGNOSE_PROMPT_TEMPLATE.format(
                    disease=request.disease.replace("_", " "),
                    confidence=round(request.confidence, 1),
                ),
            },
        ],
        "stream": False,
        "temperature": 0.3,
        "max_tokens": 280,
    }

    try:
        data = await _post_groq_chat_completion(client, payload)
        choices = data.get("choices", [])
        if not choices:
            return DiagnoseResponse(
                steps=["Please retake the scan or ask again in Plant AI chat."]
            )

        reply = choices[0].get("message", {}).get("content", "").strip()
        steps = _parse_numbered_steps(reply)
        if not steps:
            steps = [
                line.strip("-• ").strip()
                for line in reply.splitlines()
                if line.strip()
            ]
        if len(steps) > 5:
            steps = steps[:5]
        if not steps:
            steps = ["Please retake the scan or ask again in Plant AI chat."]

        return DiagnoseResponse(steps=steps)

    except httpx.ConnectError:
        raise HTTPException(
            status_code=503,
            detail="Cannot connect to Groq Cloud. Please check your internet connection.",
        )
    except httpx.TimeoutException:
        raise HTTPException(
            status_code=504,
            detail="Groq took too long to respond. Please try again.",
        )
    except httpx.HTTPStatusError as e:
        raise HTTPException(
            status_code=502,
            detail=f"Groq returned an error: {e.response.text}",
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Unexpected error: {str(e)}",
        )


@app.post("/translate", response_model=TranslateResponse)
async def translate(request: TranslateRequest):
    """
    Proxy translation requests to the Google Translate API.
    Keeps the API key server-side only.
    """
    if not GOOGLE_TRANSLATE_API_KEY:
        raise HTTPException(
            status_code=500,
            detail="GOOGLE_TRANSLATE_API_KEY is not configured on the server.",
        )

    client: httpx.AsyncClient = app.state.http_client
    translations = []

    try:
        for text in request.texts:
            resp = await client.post(
                "https://translation.googleapis.com/language/translate/v2",
                params={"key": GOOGLE_TRANSLATE_API_KEY},
                json={
                    "q": text,
                    "target": request.target_language,
                    "source": "en",
                    "format": "text",
                },
            )
            resp.raise_for_status()
            data = resp.json()
            translated = (
                data.get("data", {})
                .get("translations", [{}])[0]
                .get("translatedText", text)
            )
            translations.append(translated)

        return TranslateResponse(translations=translations)

    except httpx.HTTPStatusError as e:
        raise HTTPException(
            status_code=502,
            detail=f"Google Translate error: {e.response.text}",
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Translation error: {str(e)}",
        )




async def _post_groq_chat_completion(
    client: httpx.AsyncClient,
    payload: dict,
) -> dict:
    resp = await client.post(
        f"{GROQ_BASE_URL}/chat/completions",
        json=payload,
        headers={
            "Authorization": f"Bearer {GROQ_API_KEY}",
            "Content-Type": "application/json",
        },
    )
    resp.raise_for_status()
    return resp.json()


def _parse_numbered_steps(text: str) -> list[str]:
    steps: list[str] = []
    for line in text.splitlines():
        match = re.match(r"^\s*\d+[\.\)\:]\s*(.+)", line.strip())
        if match:
            step = match.group(1).strip()
            if step:
                steps.append(step)
    return steps


def _build_scan_history_block(scans: list[ScanHistoryItem]) -> str:
    """
    Format the user's recent scans into a structured context block that is
    appended to Tomo's system prompt before each /chat request.
    """
    if not scans:
        return (
            "--- USER'S RECENT SCAN HISTORY ---\n"
            "No recent scans found. Encourage the user to scan a tomato leaf using "
            "the Identify or Diagnose feature to get started.\n"
            "----------------------------------"
        )

    lines = ["--- USER'S RECENT SCAN HISTORY ---"]
    for i, s in enumerate(scans, start=1):
        scan_type_label = s.scanType.strip().capitalize() if s.scanType else "Identify"
        # Flag unreliable scans so Tomo doesn't treat them as certain
        reliability = ""
        if s.confidence < 40:
            reliability = " [VERY UNRELIABLE — likely incorrect, do not base advice on this]"
        elif s.confidence < 60:
            reliability = " [UNCERTAIN — may be incorrect, advise with caution]"
        lines.append(
            f"{i}. Disease: {s.disease} | "
            f"Confidence: {s.confidence:.1f}% ({s.confidenceLabel}){reliability} | "
            f"Scanned: {s.timestamp} | "
            f"Type: {scan_type_label}"
        )
    lines.append("----------------------------------")
    lines.append(
        "Use this scan history to give personalized, context-aware advice when the "
        "user asks about their plants, recent detections, or what to do next. "
        "If a scan is marked UNCERTAIN or VERY UNRELIABLE, do not give definitive "
        "treatment advice based on it — instead recommend retaking the photo."
    )
    return "\n".join(lines)
