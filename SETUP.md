# Firebase & Local AI Setup Guide for TomoLeafNet

This guide walks you through configuring the complete backend for TomoLeafNet from scratch, including the local Gemma 4 AI chat powered by Ollama.

---

## Prerequisites

- [Node.js](https://nodejs.org/) v20+ installed
- [Python](https://www.python.org/) 3.10+ installed
- [Flutter SDK](https://docs.flutter.dev/get-started/install) installed
- [Ollama](https://ollama.com/) installed (for Plant AI Chat)
- A Google account
- Android Studio or Xcode (for platform builds)

---

## Step 1 — Create a Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click **Create a project**
3. Name it `TomoLeafNet`
4. Enable or disable Google Analytics (optional)
5. Select the default GCP region closest to your target users (e.g., `asia-southeast1` for the Philippines)
6. Click **Create project**

---

## Step 2 — Register the Flutter App on Firebase

### Install Firebase CLI & FlutterFire CLI

```bash
npm install -g firebase-tools
firebase login
dart pub global activate flutterfire_cli
```

### Auto-configure with FlutterFire CLI

```bash
cd MOBILE_APP
flutterfire configure
```

This will:
- Register your Android and iOS apps in Firebase
- Download `google-services.json` and `GoogleService-Info.plist`
- Generate `lib/firebase_options.dart` with your project's configuration

### Verify file placement

- `MOBILE_APP/android/app/google-services.json` — Android config
- `MOBILE_APP/ios/Runner/GoogleService-Info.plist` — iOS config
- `MOBILE_APP/lib/firebase_options.dart` — Dart config (auto-generated)

> **Important:** These files are already in `.gitignore` and should NOT be committed to the repository.

---

## Step 3 — Enable Firebase Authentication

1. In the Firebase Console, go to **Authentication** > **Sign-in method**
2. Enable the following providers:

### Email/Password
- Click **Email/Password** > **Enable** > **Save**

### Google Sign-In
- Click **Google** > **Enable**
- Set your support email
- Click **Save**

### Android SHA Fingerprints (required for Google Sign-In)

Generate SHA fingerprints:

```bash
cd MOBILE_APP/android
./gradlew signingReport
```

Copy the `SHA-1` and `SHA-256` from the `debug` variant.

In Firebase Console:
1. Go to **Project Settings** > **Your apps** > **Android app**
2. Click **Add fingerprint**
3. Paste both SHA-1 and SHA-256

---

## Step 4 — Set Up Cloud Firestore

1. In Firebase Console, go to **Firestore Database** > **Create database**
2. Select **Production mode** (strict security rules)
3. Choose region: `asia-southeast1`
4. Click **Create**

### Deploy Security Rules

```bash
cd firebase
firebase deploy --only firestore:rules
```

This deploys the rules from `firebase/firestore.rules`:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

### Firestore Data Structure

```
users/{uid}
├── name: string
├── email: string
├── profilePhotoUrl: string (nullable)
├── registrationDate: timestamp
└── locationPreference: string (nullable)
    └── scans/{scanId}
        ├── uid: string
        ├── imageUrl: string
        ├── predictedDisease: string
        ├── confidenceScore: number
        ├── confidenceLabel: string
        ├── timestamp: timestamp
        └── gpsCoordinates: geopoint (nullable)
```

---

## Step 5 — Set Up Firebase Cloud Storage

1. In Firebase Console, go to **Storage** > **Get started**
2. Select **Production mode**
3. Choose region: `asia-southeast1`
4. Click **Done**

### Deploy Storage Rules

```bash
cd firebase
firebase deploy --only storage
```

This deploys the rules from `firebase/storage.rules`:

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /scan_images/{uid}/{allPaths=**} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

### Storage Structure

```
scan_images/{uid}/{scanId}.jpg
```

---

## Step 6 — Set Up and Deploy Cloud Functions (Weather)

### Install Dependencies

```bash
cd firebase/functions
npm install
```

### Set API Key Secret

Store the OpenWeatherMap API key as a Firebase secret:

```bash
firebase functions:secrets:set OPENWEATHER_API_KEY
# Paste your OpenWeatherMap API key when prompted
```

> **Note:** The `GEMMA_API_KEY` secret is no longer needed. Chat now uses Gemma 4 running locally via Ollama (see Step 6B below).

### Deploy Functions

```bash
cd firebase
firebase deploy --only functions
```

### Verify Deployment

After deployment, check the Firebase Console:
1. Go to **Functions** > **Dashboard**
2. Confirm the function is listed:
   - `weatherProxy` (asia-southeast1)

### Cloud Functions Overview

| Function | Purpose | Auth Required |
|----------|---------|---------------|
| `weatherProxy` | Fetches weather from OpenWeatherMap | Yes |

---

## Step 6B — Set Up Gemma 4 + Ollama for Plant AI Chat

The Plant AI Chat feature uses Gemma 4 running **locally** on your development machine via Ollama, bridged by a FastAPI backend server:

```
Flutter App (Mobile)  →  FastAPI Backend (dev machine :8000)  →  Ollama (:11434)  →  Gemma 4
```

### Step 6B.1 — Install Ollama

Download and install Ollama from [ollama.com](https://ollama.com/) for your OS:

- **Windows** — Run the `.exe` installer
- **macOS** — Unpack the zip and move Ollama to `/Applications/`
- **Linux** — Run the installer script: `curl -fsSL https://ollama.com/install.sh | sh`

Verify the installation:

```bash
ollama --version
```

### Step 6B.2 — Pull the Gemma 4 Model

Download the recommended Gemma 4 model:

```bash
# Recommended for most laptops (~5GB RAM)
ollama pull gemma4:e4b
```

**Alternative model sizes:**

| Model | RAM Required | Best For |
|-------|-------------|----------|
| `gemma4:e2b` | ~3 GB | Fastest, mobile/edge, 128K context |
| `gemma4:e4b` | ~5 GB | **Recommended** — balanced speed & quality, 128K context |
| `gemma4:26b` | ~17 GB | High quality MoE, dedicated GPU, 256K context |
| `gemma4:31b` | ~20 GB | Highest quality, consumer GPU workstation, 256K context |

Verify the model is downloaded:

```bash
ollama list
```

### Step 6B.3 — Start the Ollama Server

Ollama starts automatically after installation. To start it manually:

```bash
ollama serve
```

To prevent Ollama from unloading the model after 5 minutes of inactivity:

```bash
# Linux / macOS
OLLAMA_KEEP_ALIVE=-1 ollama serve

# Windows (PowerShell)
$env:OLLAMA_KEEP_ALIVE="-1"; ollama serve
```

Test the Ollama API:

```bash
curl http://localhost:11434/api/chat -d '{
  "model": "gemma4:e4b",
  "messages": [{"role": "user", "content": "Hello"}],
  "stream": false
}'
```

### Step 6B.4 — Set Up the FastAPI Backend Server

Navigate to the `backend/` directory and install dependencies:

```bash
cd backend
pip install -r requirements.txt
```

Configure the `.env` file (defaults should work for most setups):

```
OLLAMA_HOST=http://localhost:11434
OLLAMA_MODEL=gemma4:e4b
```

> Change `OLLAMA_MODEL` if you pulled a different model size in Step 6B.2.

Start the FastAPI server:

```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Confirm the server is running:
- Visit `http://localhost:8000/docs` in a browser (interactive API docs)
- Check health: `curl http://localhost:8000/health`
- Test chat:
  ```bash
  curl -X POST http://localhost:8000/chat ^
    -H "Content-Type: application/json" ^
    -d "{\"message\": \"Why are my tomato leaves yellow?\", \"history\": []}"
  ```

### Step 6B.5 — Find Your Development Machine's Local IP

The Flutter app on a mobile device needs to reach the FastAPI server via your machine's local network IP:

- **Windows:** `ipconfig` → look for **IPv4 Address** under your WiFi adapter
- **macOS / Linux:** `ifconfig` or `ip addr` → look for `inet` address on `en0` or `wlan0`

Update `MOBILE_APP/lib/core/config/app_config.dart` with your IP:

```dart
static const String chatBackendUrl = 'http://192.168.x.x:8000/chat';
static const String chatBackendHealthUrl = 'http://192.168.x.x:8000/health';
```

> **Important:** Both the development machine and the mobile device must be connected to the **same WiFi network**.

### Step 6B.6 — Keep Ollama Running in the Background

- **Windows:** Ollama automatically runs as a background service after installation
- **macOS:** Enable Ollama to launch at login via the menu bar icon → **Launch at Login**
- **Linux:** Create a systemd service or run in a screen/tmux session

---

## Step 7 — Configure Firebase Billing

Cloud Functions require the **Blaze (pay-as-you-go)** plan.

### Free Tier Allowances

| Service | Free Tier |
|---------|-----------|
| Authentication | Unlimited email/password users |
| Firestore | 1 GB storage, 50K reads/day, 20K writes/day |
| Cloud Storage | 5 GB storage, 1 GB/day download |
| Cloud Functions | 2M invocations/month, 400K GB-seconds |

### Set Budget Alert

1. In Firebase Console, go to **Usage and billing** > **Details & settings**
2. Click **Set budget alerts**
3. Set a monthly budget (e.g., $5 USD) to receive warnings before any charges occur

For a small-scale app with fewer than 1,000 users, costs should remain within the free tier.

---

## Step 8 — Test the Full Backend

### Run the Flutter App

```bash
cd MOBILE_APP
flutter pub get
flutter run
```

### Test Each Flow

1. **Registration** — Create a new account with email/password. Check Firestore Console to verify the user document was created under `users/{uid}`.

2. **Google Sign-In** — Sign in with Google. Verify the user profile appears in Firestore.

3. **Scan & Save** — Capture or pick a leaf image. After prediction completes:
   - Check Firestore: `users/{uid}/scans/{scanId}` should contain the prediction data
   - Check Cloud Storage: `scan_images/{uid}/{scanId}.jpg` should contain the image

4. **Scan History** — Navigate to "My Plants" tab. Verify scans appear with thumbnails and disease labels.

5. **Chat** — Send a message in the Chat tab. Verify the response comes from Gemma 4 via the local Ollama backend. Test these messages:
   - "Why are my tomato leaves turning yellow?"
   - "How do I treat Late Blight?"
   - "What does Bacterial Spot look like?"

6. **Weather** — Verify the home screen loads weather via the Cloud Function proxy.

7. **Sign Out** — Tap Sign Out in the More tab. Verify you're redirected to the login screen.

### Monitor Logs

```bash
# FastAPI server logs (visible in the terminal running uvicorn)

# Check Ollama model status
ollama ps

# Firebase Cloud Function logs
firebase functions:log
```

---

## Step 9 — Push to GitHub Safely

### Verify .gitignore Entries

Confirm these files are excluded from Git:

```
# In MOBILE_APP/.gitignore
/android/app/google-services.json
/ios/Runner/GoogleService-Info.plist
lib/firebase_options.dart
lib/core/config/api_keys.dart
```

### For New Developers

Any developer cloning this repo must:

1. Create their own Firebase project (Step 1)
2. Run `flutterfire configure` to generate their config files (Step 2)
3. Enable Auth providers in Firebase Console (Step 3)
4. Create Firestore and Storage databases (Steps 4-5)
5. Deploy the `weatherProxy` Cloud Function with their OpenWeatherMap API key (Step 6)
6. Install Ollama and pull the Gemma 4 model (Step 6B.1–6B.3)
7. Start the FastAPI backend server (Step 6B.4)
8. Update `app_config.dart` with their machine's local IP (Step 6B.5)

---

## Troubleshooting

### "No Firebase App" error on startup
Run `flutterfire configure` to generate `firebase_options.dart`.

### Google Sign-In fails on Android
Ensure SHA-1 and SHA-256 fingerprints are added to Firebase Console (Step 3).

### Chat shows "Unable to reach Plant AI backend"
1. Ensure Ollama is running: `ollama serve`
2. Ensure the FastAPI server is running: `uvicorn main:app --host 0.0.0.0 --port 8000`
3. Ensure your mobile device and dev machine are on the **same WiFi network**
4. Verify the IP in `app_config.dart` matches your machine's current local IP
5. Test connectivity: `curl http://<YOUR_IP>:8000/health`

### Chat shows "Ollama took too long to respond"
The Gemma 4 model may still be loading into memory. Wait 30-60 seconds and try again. First inference after loading is always slower.

### Cloud Functions return "unauthenticated"
The user must be signed in before calling weather functions.

### Cloud Functions return "internal" error
Check function logs: `firebase functions:log`. Verify the `OPENWEATHER_API_KEY` secret is set correctly.

### Firestore "permission denied"
Ensure security rules are deployed: `firebase deploy --only firestore:rules`.

### Weather shows "unavailable"
This is the graceful fallback when Cloud Functions are not yet deployed. Deploy functions first (Step 6).
