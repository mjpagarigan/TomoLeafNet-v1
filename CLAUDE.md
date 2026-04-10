# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TomoLeafNet-v1 is a tomato leaf disease detection system using a hybrid CNN-Transformer architecture (MobileNetV3Small + SpatialAttention + TransformerBlock). It classifies leaves into 5 categories: Bacterial_Spot, Early_Blight, Healthy, Late_Blight, Septoria. The project has two main parts: a Python ML training/evaluation pipeline and a Flutter mobile app for on-device inference.

## Commands

### Python (ML Pipeline)

```bash
# Setup
python -m venv venv && venv\Scripts\activate  # Windows
pip install -r REQUIREMENTS/requirements.txt

# Train model (outputs to MODEL/ and RESULTS/)
python SCRIPTS/train.py

# Test single image (edit IMG_PATH in script first)
python SCRIPTS/test_image.py

# Grad-CAM visualization (edit IMG_PATH first)
python SCRIPTS/test_gradcam.py

# Generate confusion matrix & classification report
python RESULTS/results.py

# Convert model formats
python SCRIPTS/convert_model.py                # H5 → Keras
python SCRIPTS/convert_keras_to_tflite.py      # Keras → TFLite
```

### Flutter (Mobile App)

```bash
cd MOBILE_APP
flutter pub get
flutter run
flutter build apk --release
flutter analyze                # Dart static analysis
```

## Architecture

### ML Model Pipeline (SCRIPTS/)

- **train.py** — 2-phase training: Phase 1 freezes MobileNetV3Small base (10 epochs, lr=3e-4), Phase 2 fine-tunes last 30 layers (25 epochs, lr=5e-5). Uses heavy data augmentation. Outputs `.keras` and `.tflite` models.
- **model_utils.py** — Shared utilities including two custom Keras layers: `SpatialAttention` (CBAM-style region attention for spot/lesion detection) and `TransformerBlock` (multi-head self-attention for global structure). Also handles model loading with `custom_objects` registration.
- **Input**: 224×224×3 RGB images. Preprocessing: center crop to square, then resize.
- **Output**: 5-class softmax. Model sizes: .keras ~11MB, .tflite ~1.5MB.

### Flutter App (MOBILE_APP/lib/)

- **main.dart** — Entry point with Firebase init, AuthWrapper routing, tab navigation (HomeScreen, ChatScreen, MyPlantsScreen, MoreScreen) and a center-docked FAB for camera.
- **core/config/app_config.dart** — Configuration constants including the Plant AI backend URL (local network IP for Ollama/FastAPI bridge).
- **screens/auth/** — Login, Register, Forgot Password screens + AuthWrapper (Firebase Auth state listener).
- **camera_screen.dart** → **result_screen.dart** — Capture/select image → preprocess (center crop, resize 224×224) → TFLite inference → auto-save scan to Firestore + Cloud Storage → display prediction with disease info and management tips.
- **history_screen.dart** — Real-time scan history from Firestore with swipe-to-delete and cached image thumbnails.
- **chat_screen.dart** — Llama 3.1 AI chatbot via FastAPI backend → Groq Cloud. UI title: "Plant AI (Llama 3.1)".
- **theme_provider.dart** — Dark/light mode via Provider pattern.
- **weather_service.dart** — Location + weather via Cloud Functions proxy (no API key in app binary).
- **services/chat_service.dart** — HTTP client for Plant AI chat, sends messages to the FastAPI backend which forwards to Groq Cloud (Llama 3.1).
- **services/** — `AuthService`, `FirestoreService`, `StorageService`, `CloudFunctionsService` (weather only), `ChatService` (Groq via FastAPI).
- **models/** — `UserModel`, `ScanModel` — Firestore data models with serialization.

### AI Backend (backend/)

- **main.py** — FastAPI server bridging Flutter ↔ Groq Cloud. Exposes `/chat` (POST), `/health` (GET), and `/` (GET) endpoints. Forwards messages to `llama-3.1-8b-instant` via Groq's OpenAI-compatible REST API at `https://api.groq.com/openai/v1`.
- **requirements.txt** — Python dependencies: `fastapi`, `uvicorn`, `httpx`, `python-dotenv`.
- **.env** — Configuration for `GROQ_API_KEY` and `GROQ_MODEL` (default: `gemma2-9b-it`). Gitignored — use `.env.example` as template.
- **render.yaml** — Render Infrastructure-as-Code config for one-click cloud deployment.
- **Deployment**: Designed to run on Render free tier (auto-sleeps after 15 min inactivity, cold start ~30s). Can also run locally via `uvicorn main:app --host 0.0.0.0 --port 8000 --reload`.

### Firebase Backend (firebase/)

- **functions/index.js** — Cloud Function: `weatherProxy` (OpenWeatherMap API). Enforces Firebase Auth and uses server-side secrets.
- **firestore.rules** — Users can only read/write their own `users/{uid}/**` documents.
- **storage.rules** — Users can only read/write their own `scan_images/{uid}/**` files.
- **firebase.json** — Firebase project configuration.

### UI Design System

The mobile application utilizes a highly customized, premium high-fidelity design system:
- **Typography**: `Space Grotesk` globally.
- **Primary Colors**: Deep Green (`#309249`) and vibrant gradient accents. Neon greens have been deprecated in favor of a cohesive rich botanical palette.
- **Design Elements**: Features "Floating glass pill" components, adaptive heavy drop shadows (0.18 opacity in light mode, 0.55 in dark mode), and pillowy `24px - 30px` border radii.
- **Dynamic Navigation**: Clean layout logic utilizing a transparent notched `BottomAppBar` with an intelligently dynamic Floating Action Button (hides automatically on text-heavy screens like Chat).

### Data Layout

- **DATA-SPLIT/** — Training data organized as `train/`, `val/`, `test/` with ~700 images per class.
- **DATA-LABEL/** — Validation/test dataset organized by disease class folders.
- **MODEL/** — Trained model files (.keras, .h5, .tflite).
- **RESULTS/** — Evaluation outputs (confusion matrix, training curves, metrics JSON).

## Key Technical Details

- TensorFlow 2.10.0 is pinned in requirements — custom layers use `tf.keras` APIs.
- Custom layers (`SpatialAttention`, `TransformerBlock`) must be registered via `custom_objects` when loading models (handled in `model_utils.py`).
- The TFLite model is quantized for mobile deployment and bundled in `MOBILE_APP/assets/`.
- Flutter app uses `tflite_flutter` 0.12.0 for on-device inference.
- Codemagic CI is configured via `codemagic.yaml` for mobile builds.
- **Firebase backend** provides auth, Firestore database, Cloud Storage, and Cloud Functions (weather only). See `SETUP.md` for configuration.
- **Plant AI Chat** uses **Groq Cloud** hosting `llama-3.1-8b-instant`, bridged by a FastAPI server. The `GROQ_API_KEY` is stored only on the server (Render env var or local `.env`) — never shipped in the APK.
- **Chat backend URL config** in `app_config.dart` uses a `BackendMode` enum with four modes: `render` (production, cloud-hosted, works anywhere 24/7), `ngrok` (public tunnel to local FastAPI), `localWifi` (local FastAPI via dev machine IP), and `emulator` (local FastAPI via `10.0.2.2`). Switch by changing the `backendMode` constant — default is `render`.
- **Render deployment**: `backend/render.yaml` defines a free-tier web service. On push to main, Render auto-deploys the FastAPI backend with `GROQ_API_KEY` injected as an environment variable. Free tier spins down after 15 min inactivity (~30s cold start on first request).
- **No weather API keys in app binary** — OpenWeatherMap key is stored as a Firebase secret and accessed only through the `weatherProxy` Cloud Function.
- **Offline persistence** is enabled for Firestore — scan history works without connectivity.
- Firebase config files (`google-services.json`, `GoogleService-Info.plist`, `firebase_options.dart`) are gitignored. New developers must run `flutterfire configure`.

## Known Issues

The model has moderate overfitting (val accuracy ~87% vs train ~94%). Detailed diagnosis and improvement recommendations are documented in `training_diagnosis.md`.
