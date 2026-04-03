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

- **main.dart** — Entry point with tab navigation (HomeScreen, ChatScreen, MyPlantsScreen, MoreScreen) and a center-docked FAB for camera.
- **camera_screen.dart** → **result_screen.dart** — Capture/select image → preprocess (center crop, resize 224×224) → TFLite inference → display prediction with disease info and management tips.
- **chat_screen.dart** — Gemini AI chatbot for follow-up questions about diseases.
- **theme_provider.dart** — Dark/light mode via Provider pattern.
- **weather_service.dart** — Location + weather API integration.
- **core/config/api_keys.dart** — API key storage (Gemini, weather).

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

## Known Issues

The model has moderate overfitting (val accuracy ~87% vs train ~94%). Detailed diagnosis and improvement recommendations are documented in `training_diagnosis.md`.
