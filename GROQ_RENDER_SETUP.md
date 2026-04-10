# Plant AI Chat — Groq + Render Setup Guide

This guide walks you through deploying the TomoLeafNet Plant AI Chat to the cloud using **Groq** (for the LLM) and **Render** (for the FastAPI backend). Once set up, the chat will work **from anywhere, 24/7**, with no need to keep your PC running.

## Architecture

```
Flutter App (Mobile)
    ↓
FastAPI Backend on Render (cloud)
    ↓
Groq Cloud API
    ↓
Llama 3.1 8B Instant (llama-3.1-8b-instant)
```

---

## Part 1 — Get a Free Groq API Key

### Step 1: Sign up for Groq
1. Go to **https://console.groq.com/login**
2. Sign in with Google/GitHub (free, no credit card)
3. After login, go to **https://console.groq.com/keys**
4. Click **"Create API Key"**, give it a name like `tomoleafnet`
5. **Copy the API key immediately** — you won't be able to see it again
6. Store it somewhere safe (you'll paste it into Render in Part 3)

### Step 2: Verify the API key works (optional)
Open PowerShell and test:

```powershell
$env:GROQ_API_KEY = "your_api_key_here"
Invoke-RestMethod -Uri "https://api.groq.com/openai/v1/chat/completions" `
  -Method Post `
  -Headers @{"Authorization"="Bearer $env:GROQ_API_KEY"; "Content-Type"="application/json"} `
  -Body '{"model":"llama-3.1-8b-instant","messages":[{"role":"user","content":"hello"}]}'
```

You should get a response with a `choices` array.

---

## Part 2 — Test the Backend Locally (Optional)

Before deploying, you can verify the backend works locally.

### Step 1: Configure the local `.env`
Edit [backend/.env](backend/.env) (create it from `.env.example` if missing):

```env
GROQ_API_KEY=your_actual_groq_api_key_here
GROQ_MODEL=llama-3.1-8b-instant
```

> **IMPORTANT:** Never commit this file. It's already in `.gitignore`.

### Step 2: Install dependencies and run
```powershell
cd backend
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### Step 3: Test the health endpoint
In a new terminal:
```powershell
Invoke-RestMethod -Uri "http://localhost:8000/health"
```

You should see `"status": "ok"` and `"groq": "connected"`.

### Step 4: Test the chat endpoint
```powershell
Invoke-RestMethod -Uri "http://localhost:8000/chat" `
  -Method Post `
  -ContentType "application/json" `
  -Body '{"message":"Why are my tomato leaves turning yellow?","history":[]}'
```

You should get a `reply` field with a plant-health-focused response in 1-2 seconds.

---

## Part 3 — Deploy the Backend to Render

### Step 1: Create a Render account
1. Go to **https://render.com**
2. Sign up with your **GitHub account** (easiest — Render will be able to read your repos)
3. Authorize Render to access your GitHub

### Step 2: Push your code to GitHub
Make sure the latest changes (including [backend/render.yaml](backend/render.yaml)) are pushed:

```powershell
git add .
git commit -m "Migrate Plant AI Chat to Groq + Render"
git push origin main
```

### Step 3: Create a new Web Service on Render

**Option A — Using render.yaml (automated):**
1. On Render dashboard, click **"New +"** → **"Blueprint"**
2. Connect your **TomoLeafNet-v1** repository
3. Render will detect [backend/render.yaml](backend/render.yaml) automatically
4. Click **"Apply"**
5. Skip to Step 4

**Option B — Manual setup:**
1. On Render dashboard, click **"New +"** → **"Web Service"**
2. Connect your **TomoLeafNet-v1** repository
3. Configure the service:
   - **Name:** `tomoleafnet-plant-ai`
   - **Region:** Singapore (closest to Philippines) or your nearest region
   - **Branch:** `main`
   - **Root Directory:** `backend`
   - **Runtime:** `Python 3`
   - **Build Command:** `pip install -r requirements.txt`
   - **Start Command:** `uvicorn main:app --host 0.0.0.0 --port $PORT`
   - **Plan:** `Free`
4. Click **"Create Web Service"**

### Step 4: Add the Groq API key as an environment variable
1. On your service's page, click **"Environment"** in the left sidebar
2. Click **"Add Environment Variable"**
3. Add:
   - Key: `GROQ_API_KEY`
   - Value: *paste your Groq API key from Part 1*
4. If not already set, also add:
   - Key: `GROQ_MODEL`
   - Value: `llama-3.1-8b-instant`
5. Click **"Save Changes"** — Render will redeploy automatically

### Step 5: Wait for deployment
1. Go to the **"Logs"** tab
2. Wait for:
   ```
   Uvicorn running on http://0.0.0.0:10000
   Application startup complete.
   ```
3. This usually takes 2-5 minutes on first deploy

### Step 6: Test the deployed backend
1. On the service page, copy your URL at the top — looks like:
   ```
   https://tomoleafnet-plant-ai.onrender.com
   ```
2. Open it in a browser — you should see:
   ```json
   {"service":"TomoLeafNet Plant AI Backend","status":"running"}
   ```
3. Test the health endpoint: visit `https://tomoleafnet-plant-ai.onrender.com/health`
   You should see `"status": "ok"` and `"groq": "connected"`

---

## Part 4 — Update the Flutter App

### Step 1: Update the Render URL in app_config.dart
Open [MOBILE_APP/lib/core/config/app_config.dart](MOBILE_APP/lib/core/config/app_config.dart) and update:

```dart
static const String renderUrl = 'https://tomoleafnet-plant-ai.onrender.com';
```

(Replace with your actual Render URL from Part 3, Step 6.)

Make sure `backendMode` is set to `BackendMode.render`:

```dart
static const BackendMode backendMode = BackendMode.render;
```

### Step 2: Rebuild the APK
```powershell
cd MOBILE_APP
flutter build apk --release
```

The APK will be at:
```
MOBILE_APP/build/app/outputs/flutter-apk/app-release.apk
```

### Step 3: Install and test
1. Copy the APK to your phone (USB, email, cloud drive, etc.)
2. Install it (you may need to enable "Install unknown apps")
3. Open the app, sign in, go to **Chat**
4. Ask: *"Why are my tomato leaves turning yellow?"*

The first response may take **~30 seconds** (Render free tier cold start). Subsequent messages should respond in **1-3 seconds**.

---

## Part 5 — Understanding the Free Tier Limits

### Groq Free Tier
- **Requests per minute:** 30
- **Requests per day:** 14,400
- **Tokens per minute:** 15,000
- **Model:** `llama-3.1-8b-instant` (8 billion parameters, 560 tokens/sec)
- More than enough for personal use and demos

### Render Free Tier
- **750 hours/month** of runtime (enough for one service to run 24/7)
- **512 MB RAM** (plenty for FastAPI)
- **Auto-sleep:** Service sleeps after **15 minutes** of inactivity
- **Cold start:** ~30 seconds to wake up on the next request
- **Bandwidth:** 100 GB/month

### Handling Cold Starts
If the 30-second cold start is a problem, you can:
1. **Upgrade to Render's Starter plan** ($7/month, no sleep)
2. **Set up a free cron job** (e.g., via [cron-job.org](https://cron-job.org)) to ping `https://tomoleafnet-plant-ai.onrender.com/health` every 10 minutes to keep the service awake

---

## Part 6 — Troubleshooting

### "GROQ_API_KEY is not configured on the server"
- You forgot to add the env var on Render
- Go to the service → **Environment** → add `GROQ_API_KEY` and save

### "Unable to reach Plant AI backend" on the phone
- Check that your Render service is **Live** (not Suspended) in the dashboard
- Visit the Render URL in a browser to test
- Check the `renderUrl` in [app_config.dart](MOBILE_APP/lib/core/config/app_config.dart) matches exactly (including `https://`)
- Rebuild the APK after changing the URL

### First message takes forever
- Normal — Render free tier cold start takes ~30s
- Subsequent messages should be fast
- See "Handling Cold Starts" above

### Render build fails
- Check the **Logs** tab for the error
- Make sure `backend/requirements.txt` exists and is valid
- Make sure the root directory is set to `backend`

### Groq returns 401 Unauthorized
- Your API key is invalid or expired
- Generate a new one at https://console.groq.com/keys
- Update it in Render's **Environment** tab

### Chat works but responses are cut off
- Llama 3.1 8B has a 131K-token context limit — very long conversations may need trimming
- Clear the chat and start fresh

---

## Part 7 — Switching Between Backend Modes

You can still use the local FastAPI backend for development without redeploying. Just change one line in [app_config.dart](MOBILE_APP/lib/core/config/app_config.dart):

```dart
// Production — uses Render
static const BackendMode backendMode = BackendMode.render;

// Development — uses local FastAPI on Android emulator
// static const BackendMode backendMode = BackendMode.emulator;

// Development — uses local FastAPI on same WiFi as physical phone
// static const BackendMode backendMode = BackendMode.localWifi;

// Development — uses local FastAPI exposed via ngrok public tunnel
// static const BackendMode backendMode = BackendMode.ngrok;
```

Rebuild the APK after changing.

---

## Summary

| Component | Where it lives | Cost |
|-----------|---------------|------|
| FastAPI backend | Render (cloud) | Free |
| Llama 3.1 8B LLM | Groq (cloud) | Free |
| Flutter app | Your phone | Free |
| Your PC | **Off** — no longer needed | N/A |

Once this is set up, the Plant AI Chat will work from any device, on any network, with your PC turned off. Enjoy!
