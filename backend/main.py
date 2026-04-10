"""
FastAPI backend server for TomoLeafNet Plant AI Chat.

Bridges the Flutter mobile app and Groq Cloud (hosting Gemma 2).
The mobile app sends chat requests here, and this server forwards
them to the Groq OpenAI-compatible REST API.

Usage:
    uvicorn main:app --host 0.0.0.0 --port 8000 --reload
"""

import os
from contextlib import asynccontextmanager

import httpx
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

load_dotenv()

GROQ_API_KEY = os.getenv("GROQ_API_KEY", "")
GROQ_MODEL = os.getenv("GROQ_MODEL", "llama-3.1-8b-instant")
GROQ_BASE_URL = "https://api.groq.com/openai/v1"

SYSTEM_PROMPT = (
    "You are TomoLeafNet's tomato plant health assistant. "
    "Answer in 2-4 short sentences max. Be direct and practical. "
    "Use simple farmer-friendly words. No long intros, no disclaimers, no headings, no bullet lists unless the user explicitly asks. "
    "If suggesting a treatment, give just 1-2 concrete actions. "
    "Only discuss tomato/plant health topics."
)

# ── Shared HTTP client (reused across requests) ──────────────────────


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage the shared httpx.AsyncClient lifecycle."""
    app.state.http_client = httpx.AsyncClient(timeout=60.0)
    yield
    await app.state.http_client.aclose()


# ── FastAPI app ──────────────────────────────────────────────────────

app = FastAPI(
    title="TomoLeafNet Plant AI Backend",
    description="Bridges Flutter ↔ Groq Cloud (Gemma 2) for plant health chat.",
    version="2.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Request / Response models ────────────────────────────────────────


class HistoryMessage(BaseModel):
    role: str  # "user" or "assistant"
    text: str


class ChatRequest(BaseModel):
    message: str
    history: list[HistoryMessage] = []


class ChatResponse(BaseModel):
    reply: str


# ── Endpoints ────────────────────────────────────────────────────────


@app.get("/")
async def root():
    """Simple root endpoint so Render's health checks pass."""
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
    forward it to Groq Cloud (Gemma 2), and return the AI response.
    """
    if not GROQ_API_KEY:
        raise HTTPException(
            status_code=500,
            detail="GROQ_API_KEY is not configured on the server.",
        )

    client: httpx.AsyncClient = app.state.http_client

    # Build the OpenAI-compatible messages array
    messages = [{"role": "system", "content": SYSTEM_PROMPT}]

    # Append conversation history
    for msg in request.history:
        role = "user" if msg.role == "user" else "assistant"
        messages.append({"role": role, "content": msg.text})

    # Append the current user message
    messages.append({"role": "user", "content": request.message})

    # Forward to Groq
    payload = {
        "model": GROQ_MODEL,
        "messages": messages,
        "stream": False,
        "temperature": 0.5,
        "max_tokens": 180,
    }

    try:
        resp = await client.post(
            f"{GROQ_BASE_URL}/chat/completions",
            json=payload,
            headers={
                "Authorization": f"Bearer {GROQ_API_KEY}",
                "Content-Type": "application/json",
            },
        )
        resp.raise_for_status()
        data = resp.json()
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
