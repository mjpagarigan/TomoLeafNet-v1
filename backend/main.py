"""
FastAPI backend server for TomoLeafNet Plant AI Chat.

Bridges the Flutter mobile app and Ollama running Gemma 4 locally.
The mobile app sends chat requests here, and this server forwards
them to the Ollama REST API at http://localhost:11434.

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

OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://localhost:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "gemma4:e4b")

SYSTEM_PROMPT = (
    "You are a plant health assistant for TomoLeafNet, specializing in tomato "
    "leaf disease detection and treatment. Help farmers identify symptoms, "
    "understand diseases, and recommend practical treatments based on their "
    "descriptions. Keep all responses clear, concise, and farmer-friendly. "
    "Avoid overly technical language. Focus only on plant health topics."
)

# ── Shared HTTP client (reused across requests) ──────────────────────


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage the shared httpx.AsyncClient lifecycle."""
    app.state.http_client = httpx.AsyncClient(timeout=120.0)
    yield
    await app.state.http_client.aclose()


# ── FastAPI app ──────────────────────────────────────────────────────

app = FastAPI(
    title="TomoLeafNet Plant AI Backend",
    description="Bridges Flutter ↔ Ollama (Gemma 4) for plant health chat.",
    version="1.0.0",
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


@app.get("/health")
async def health_check():
    """Check if the backend and Ollama are reachable."""
    client: httpx.AsyncClient = app.state.http_client
    try:
        resp = await client.get(f"{OLLAMA_HOST}/api/tags")
        resp.raise_for_status()
        models = resp.json().get("models", [])
        model_names = [m.get("name", "") for m in models]
        return {
            "status": "ok",
            "ollama": "connected",
            "configured_model": OLLAMA_MODEL,
            "available_models": model_names,
        }
    except httpx.ConnectError:
        return {
            "status": "degraded",
            "ollama": "unreachable",
            "detail": f"Cannot connect to Ollama at {OLLAMA_HOST}. Is it running?",
        }
    except Exception as e:
        return {
            "status": "degraded",
            "ollama": "error",
            "detail": str(e),
        }


@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    """
    Accept a user message + conversation history from the Flutter app,
    forward it to Ollama (Gemma 4), and return the AI response.
    """
    client: httpx.AsyncClient = app.state.http_client

    # Build the Ollama messages array
    messages = [{"role": "system", "content": SYSTEM_PROMPT}]

    # Append conversation history (excluding the current message)
    for msg in request.history:
        role = "user" if msg.role == "user" else "assistant"
        messages.append({"role": role, "content": msg.text})

    # Append the current user message
    messages.append({"role": "user", "content": request.message})

    # Forward to Ollama
    payload = {
        "model": OLLAMA_MODEL,
        "messages": messages,
        "stream": False,
    }

    try:
        resp = await client.post(
            f"{OLLAMA_HOST}/api/chat",
            json=payload,
        )
        resp.raise_for_status()
        data = resp.json()
        reply = data.get("message", {}).get("content", "")
        if not reply:
            reply = "Sorry, I could not generate a response."
        return ChatResponse(reply=reply)

    except httpx.ConnectError:
        raise HTTPException(
            status_code=503,
            detail=(
                f"Cannot connect to Ollama at {OLLAMA_HOST}. "
                "Please ensure Ollama is running: ollama serve"
            ),
        )
    except httpx.TimeoutException:
        raise HTTPException(
            status_code=504,
            detail=(
                "Ollama took too long to respond. "
                "The model may still be loading — please try again."
            ),
        )
    except httpx.HTTPStatusError as e:
        raise HTTPException(
            status_code=502,
            detail=f"Ollama returned an error: {e.response.text}",
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Unexpected error: {str(e)}",
        )
