# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TomoLeafNet-v1 is a tomato leaf disease detection system using MobileNetV3Large. It classifies leaves into 5 categories: Early_Blight, Healthy, Leaf_Miner, Leaf_Mold, Not_Tomato. The Not_Tomato class is a rejection class using DTD textures to filter non-tomato-leaf images. The project has two main parts: a Python ML training/evaluation pipeline and a Flutter mobile app for on-device inference.

## Commands

### Python (ML Pipeline — v4 Two-Phase Training)

```bash
# Setup
python -m venv venv && venv\Scripts\activate  # Windows
pip install tensorflow scikit-learn matplotlib seaborn

# Step 0: Balance field dataset (augment to 1k/class, split 70/15/15)
python 0_augment_field_dataset.py

# Step 1: Phase 1 warm-up on public Kaggle 4-class dataset
python 1_train_phase1.py

# Step 2: Phase 2 fine-tune on field dataset + export TFLite
python 2_train_phase2.py

# Step 3: Evaluate on unseen field test set
python 3_evaluate_metrics.py
```

### Legacy Scripts (SCRIPTS/ — v3, kept for reference)

```bash
python SCRIPTS/train.py              # Old v3 5-class training
python SCRIPTS/test_image.py         # Test single image
python SCRIPTS/test_gradcam.py       # Grad-CAM visualization
python RESULTS/results.py            # Confusion matrix & report
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

### ML Model Pipeline (Root-level scripts)

- **0_augment_field_dataset.py** — Reads raw field images from `DATA-RAW/field/`, augments each class to 1,000 images, splits 70/15/15 into `DATA-SPLIT/target_field/`. Val and test splits contain real images only.
- **1_train_phase1.py** — Phase 1 warm-up: freezes MobileNetV3Large base, trains on public 5-class dataset (`DATA-SPLIT/public_1k/`, 80/20 split, 15 epochs). Outputs `MODEL/phase1_base.keras`.
- **2_train_phase2.py** — Phase 2 fine-tuning: 3-stage progressive unfreeze (last 30 → last 60 → all layers) on field dataset with Mixup augmentation, class weights, and cosine LR warmup. Total 85 epochs. Exports `MODEL/tomoleafnet_v4_final.keras` and `MODEL/tomoleafnet_v4.tflite`.
- **3_evaluate_metrics.py** — Evaluates on unseen field test set. Outputs confusion matrix and per-class accuracy.
- **Input**: 224×224×3 RGB images. Preprocessing: center crop to square, then resize.
- **Output**: 5-class softmax (Early_Blight, Healthy, Leaf_Miner, Leaf_Mold, Not_Tomato).

### Flutter App (MOBILE_APP/lib/)

- **main.dart** — Entry point with Firebase init, AuthWrapper routing, tab navigation (HomeScreen, ChatScreen, MyPlantsScreen, MoreScreen) and a center-docked FAB for camera.
- **core/config/app_config.dart** — Configuration constants including the Plant AI backend URL (local network IP for Ollama/FastAPI bridge).
- **screens/auth/** — Login, Register, Forgot Password screens + AuthWrapper (Firebase Auth state listener).
- **camera_screen.dart** → **result_screen.dart** — Capture/select image → preprocess (center crop, resize 224×224) → TFLite inference → auto-save scan to Firestore + Cloud Storage → display prediction with disease info and management tips.
- **history_screen.dart** — Real-time scan history from Firestore with swipe-to-delete and cached image thumbnails.
- **chat_screen.dart** — Llama 3.1 AI chatbot via FastAPI backend → Groq Cloud. UI title: "Tomo — Plant Assistant".
- **theme_provider.dart** — Dark/light mode via Provider pattern.
- **weather_service.dart** — Location + weather via Cloud Functions proxy (no API key in app binary).
- **services/tflite_service.dart** — Loads `tomoleafnet_v4.tflite` and `labels.txt`, runs on-device inference with center-crop preprocessing.
- **services/chat_service.dart** — HTTP client for Plant AI chat, sends messages to the FastAPI backend which forwards to Groq Cloud (Llama 3.1).
- **services/diagnostic_guide_service.dart** — Local bilingual diagnostic guide content for the supported tomato diseases used by the Diagnose flow.
- **services/** — `AuthService`, `FirestoreService`, `StorageService`, `CloudFunctionsService` (weather only), `ChatService` (Groq via FastAPI).
- **models/** — `UserModel`, `ScanModel` — Firestore data models with serialization.

### AI Backend (backend/)

- **main.py** — FastAPI server bridging Flutter ↔ Groq Cloud. Exposes `/chat` (POST), `/translate` (POST), `/health` (GET), and `/` (GET) endpoints. Forwards chat messages to `llama-3.1-8b-instant` via Groq's OpenAI-compatible REST API at `https://api.groq.com/openai/v1`.
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

- **DATA-SPLIT/public_1k/** — Phase 1: Public 5-class dataset (80/20 train/val, 4,000/1,000 images).
- **DATA-SPLIT/target_field/** — Phase 2: Field dataset (70/15/15 train/val/test, 3,500/750/750 images). Val and test are real images only.
- **DATA-RAW/field/** — Raw field dataset (5 classes: Early_Blight, Healthy, Leaf_Miner, Leaf_Mold, Not_Tomato). Real farm images + DTD textures for Not_Tomato.
- **DATA-RAW/public/** — Raw public dataset (5 classes, 1,000 images each). Sourced from Kaggle + DTD textures.
- **MODEL/** — Trained model files: `phase1_base.keras`, `tomoleafnet_v4_final.keras`, `tomoleafnet_v4.tflite`.
- **RESULTS/** — Evaluation outputs (confusion matrix, training curves).

## Key Technical Details

- The v4 model uses MobileNetV3Large (no custom layers like SpatialAttention/TransformerBlock from v3).
- **Preprocessing is NOT embedded in the model graph.** MobileNetV3 normalization ([0,255] → [-1,1]) is applied in the dataset pipeline during training and explicitly in Flutter's `tflite_service.dart` (`pixel / 127.5 - 1.0`). This prevents TFLite conversion from silently stripping the preprocessing layer.
- Two-phase transfer learning: Phase 1 (frozen base on public data, 15 epochs) → Phase 2 (3-stage progressive unfreeze on field data: last 30 → last 60 → all layers, 85 total epochs).
- Phase 2 uses Mixup augmentation (alpha=0.1), class weights, GaussianNoise(15.0), and cosine LR with warmup. No label smoothing (Mixup already regularizes).
- CSVLogger writes epoch metrics to `RESULTS/Phase2_History.csv` — survives training crashes.
- The TFLite model is quantized (DEFAULT optimization) for mobile deployment and bundled in `MOBILE_APP/assets/`. Run `python 3_evaluate_metrics.py` to compare Keras vs TFLite accuracy.
- Flutter app uses `tflite_flutter` 0.12.0 for on-device inference with top-2 confidence gap check (ambiguous if gap < 0.15).
- Classes (alphabetical, matching TFLite output index): Early_Blight, Healthy, Leaf_Miner, Leaf_Mold, Not_Tomato.
- Not_Tomato is a rejection class using DTD texture images to filter non-tomato-leaf inputs.
- Codemagic CI is configured via `codemagic.yaml` for mobile builds.
- **Firebase backend** provides auth, Firestore database, Cloud Storage, and Cloud Functions (weather only). See `SETUP.md` for configuration.
- **Plant AI Chat** uses **Groq Cloud** hosting `llama-3.1-8b-instant`, bridged by a FastAPI server. The `GROQ_API_KEY` is stored only on the server (Render env var or local `.env`) — never shipped in the APK.
- **Chat backend URL config** in `app_config.dart` uses a `BackendMode` enum with four modes: `render` (production, cloud-hosted, works anywhere 24/7), `ngrok` (public tunnel to local FastAPI), `localWifi` (local FastAPI via dev machine IP), and `emulator` (local FastAPI via `10.0.2.2`). Switch by changing the `backendMode` constant — default is `render`.
- **Render deployment**: `backend/render.yaml` defines a free-tier web service. On push to main, Render auto-deploys the FastAPI backend with `GROQ_API_KEY` injected as an environment variable. Free tier spins down after 15 min inactivity (~30s cold start on first request).
- **No weather API keys in app binary** — OpenWeatherMap key is stored as a Firebase secret and accessed only through the `weatherProxy` Cloud Function.
- **Offline persistence** is enabled for Firestore — scan history works without connectivity.
- Firebase config files (`google-services.json`, `GoogleService-Info.plist`, `firebase_options.dart`) are gitignored. New developers must run `flutterfire configure`.
