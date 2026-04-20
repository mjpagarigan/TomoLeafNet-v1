# DIAGNOSIS.md — False Positive Root Cause Analysis

**Date:** 2026-04-20
**Scope:** End-to-end pipeline: dataset → training → TFLite export → Flutter inference
**Goal:** Identify root causes of false positives during real-world capture

---

## Finding Summary (ranked by severity)

| # | Area | Finding | Severity | File(s) |
|---|------|---------|----------|---------|
| 1 | **Preprocessing** | Disease classifier receives `[0, 255]` in Flutter; trained on `[-1, 1]` | **CRITICAL** | `MOBILE_APP/lib/services/tflite_service.dart:453-488` |
| 2 | **Preprocessing** | Live-frame disease inference also skips normalization | **CRITICAL** | `MOBILE_APP/lib/services/tflite_service.dart:142-187` |
| 3 | **Gatekeeper** | Unknown negative training set; no info on what non-leaf data was used | **HIGH** | `MOBILE_APP/lib/core/services/leaf_detector_service.dart` |
| 4 | **Gatekeeper** | No temporal smoothing — single frame can trigger "leaf detected" | **MEDIUM** | `MOBILE_APP/lib/camera_screen.dart:160-175` |
| 5 | **Dataset** | Severe class imbalance pre-augmentation (377–902 real images) | **MEDIUM** | `0_augment_field_dataset.py:200-208` |
| 6 | **Dataset** | Random split from same capture sessions inflates val/test accuracy | **MEDIUM** | `0_augment_field_dataset.py:106-161` |
| 7 | **Augmentation** | Missing real-world conditions: motion blur, shadow, rain, partial occlusion | **MEDIUM** | `2_train_phase2.py:57-65` |
| 8 | **Classifier** | No "Unknown / retake" abstain path for OOD inputs between gatekeeper and classifier | **MEDIUM** | `MOBILE_APP/lib/services/tflite_service.dart:91-131` |
| 9 | **Telemetry** | No server-side misclassification logging; feedback is per-user Firestore only | **LOW** | `MOBILE_APP/lib/services/firestore_service.dart:203-222` |
| 10 | **TFLite** | DEFAULT quantization without representative dataset | **LOW** | `2_train_phase2.py:424` |

---

## Detailed Findings

### 1. CRITICAL — Preprocessing Mismatch (Disease Classifier)

**What:** The disease classifier (MobileNetV3Large) was trained with
`tf.keras.applications.mobilenet_v3.preprocess_input`, which maps pixel values from
`[0, 255]` to `[-1, 1]`. The CLAUDE.md and Phase 1 code comments explicitly state
that preprocessing is **NOT embedded in the model graph** to avoid TFLite conversion
ambiguity.

However, in Flutter, the `_preprocessImageFile()` function
(`tflite_service.dart:453-488`) returns **raw `[0, 255]` float values** with no
normalization. The comment on line 82 incorrectly states:

> "MobileNetV3 handles normalization internally, so raw [0, 255] is passed."

This is **wrong**. The model expects `[-1, 1]`. Feeding `[0, 255]` means every
input neuron receives values 127× larger than expected, driving all activations
to saturation. The softmax will still produce a confident-looking distribution
(because softmax normalizes any input), but the predictions are essentially
**random with high confidence** — the textbook false positive pattern.

**Evidence that this is the root cause:**
- The leaf detector service (`leaf_detector_service.dart:131-140`) **does** normalize
  with `/ 127.5 - 1.0`, proving the team knows the correct formula.
- The Python evaluation script (`3_evaluate_metrics.py:64-66`) correctly applies
  `preprocess_input` before Keras and TFLite evaluation, so test-set metrics look
  fine — the bug is **Flutter-only**.
- CLAUDE.md itself documents: "Preprocessing is NOT embedded in the model graph…
  explicitly in Flutter's tflite_service.dart (pixel / 127.5 - 1.0)" — but this
  normalization was never actually implemented in the Dart code.

**Severity:** CRITICAL — this single bug makes every disease prediction in the
deployed app unreliable.

**Files:**
- `MOBILE_APP/lib/services/tflite_service.dart:453-488` (file-based path)
- `MOBILE_APP/lib/services/tflite_service.dart:142-187` (live-frame path, also missing)

---

### 2. HIGH — Gatekeeper Negative Training Data Unknown

**What:** The binary leaf detector (`tomoleafnet_detector.tflite`) classifies frames
as `tomato_leaf` vs `not_tomato_leaf`. There is no training script or dataset manifest
for this model in the repo — only the pre-built `.tflite` asset. Without knowing what
the "not_tomato_leaf" class was trained on, we cannot assess whether it will reject:

- Non-tomato plant leaves (e.g., eggplant, pepper — visually similar)
- Hands/fingers holding leaves
- Soil, sky, or indoor backgrounds
- Blurry or dark frames

If the negative class is generic ImageNet-style images, the gatekeeper will pass
many real-world non-leaf inputs because they fall outside its training distribution.

**Severity:** HIGH — a weak gatekeeper forwards bad frames to the disease classifier.

**File:** `MOBILE_APP/lib/core/services/leaf_detector_service.dart`

---

### 3. MEDIUM — No Temporal Smoothing on Gatekeeper

**What:** The camera screen processes frames every ~500ms via a timer
(`camera_screen.dart:165-175`). A single frame where `confidence >= 0.75` causes
the viewfinder to turn green ("Tomato leaf detected!"). There is no requirement
for N-of-M consecutive frames above threshold.

A momentary false positive (e.g., a green object briefly entering the frame) will
show the user a green "ready to capture" indicator, encouraging them to take a photo
of a non-leaf.

**Severity:** MEDIUM — the gatekeeper is advisory-only (users can capture regardless),
but a green indicator creates false confidence.

**File:** `MOBILE_APP/lib/camera_screen.dart:160-175`, `253`

---

### 4. MEDIUM — Class Imbalance Before Augmentation

**What:** Raw field image counts from `0_augment_field_dataset.py:200-208`:

| Class | Real Images | Synthetic Needed | Total |
|-------|------------|-----------------|-------|
| Early_Blight | 377 | 623 | 1,000 |
| Healthy | 902 | 98 | 1,000 |
| Leaf_Miner | 560 | 440 | 1,000 |
| Leaf_Mold | 386 | 614 | 1,000 |
| Not_Tomato | 500 | 500 | 1,000 |

Early_Blight and Leaf_Mold are ~62% synthetic data — the model may learn augmentation
artifacts rather than real disease features. Healthy has only 98 synthetic images,
creating a distributional gap between classes.

The val/test splits use only real images (150 each), which is correct. But Early_Blight
and Leaf_Mold each have only 377/386 real images total, so after reserving 300 for
val+test, only 77/86 real images remain in training (the rest are synthetic). The
model's training signal for these classes is dominated by augmented copies of a very
small real set.

**Severity:** MEDIUM — class weights partially compensate, but augmentation-heavy
classes are at higher risk of overfitting to specific leaf patterns.

**File:** `0_augment_field_dataset.py:200-208`

---

### 5. MEDIUM — Random Split from Same Capture Sessions

**What:** The data split in `0_augment_field_dataset.py:106-161` does a random
shuffle of all images per class, then takes first 150 for val, next 150 for test,
rest for train. If images were captured in batch sessions (e.g., multiple photos of
the same leaf, same plant, same field on the same day), then train/val/test will
contain near-duplicate images from the same session.

This causes **data leakage**: the model memorizes specific leaves/backgrounds and
achieves inflated val/test accuracy, but performs poorly on genuinely new inputs.

**Severity:** MEDIUM — cannot confirm without inspecting image filenames/metadata,
but this is a common issue with field-captured datasets and very likely present here.

**File:** `0_augment_field_dataset.py:106-161`

---

### 6. MEDIUM — Augmentation Gaps vs Real-World Capture

**What:** Current training augmentations (`2_train_phase2.py:57-65`):
- `RandomFlip("horizontal_and_vertical")` — includes vertical flip
- `RandomRotation(0.25)` — ±90°
- `RandomZoom((-0.3, 0.15))` — zoom in/out
- `RandomTranslation(0.2, 0.2)` — shift
- `RandomContrast(0.3)` — contrast jitter
- `RandomBrightness(0.3)` — brightness jitter
- `GaussianNoise(0.06)` — sensor noise (~15/255)

**Missing conditions common in Philippine field capture:**
- **Motion blur** — hand-held phone + wind
- **Random shadow / partial shade** — common under canopy
- **HSV/color jitter** — different phone cameras have different white balance
- **Partial occlusion / CoarseDropout** — fingers, other leaves, stakes
- **Perspective warp** — leaves photographed at angles
- **Rain droplets** on leaf surface

**Note on vertical flip:** Tomato leaves have a natural orientation (petiole at
bottom). Vertical flipping creates unnatural orientations that don't occur in real
use. This may slightly hurt accuracy but is unlikely to cause false positives
specifically. Low priority.

**Severity:** MEDIUM — augmentation gaps cause the model to be brittle to conditions
it hasn't seen, but these are secondary to the critical preprocessing bug.

**File:** `2_train_phase2.py:57-65`

---

### 7. MEDIUM — No Abstain Path Between Gatekeeper and Classifier

**What:** The gatekeeper runs on live frames and shows a red/green indicator. But the
actual capture + disease classification is **completely independent** — when the user
taps capture, the photo goes through `_cropToSquare` → `TFLiteService.predict()` →
disease result screen, regardless of the gatekeeper's verdict.

The result screen does have good safeguards:
- `Not_Tomato` → shows retake prompt, doesn't save (`identify_result_screen.dart:172`)
- Confidence < 60% or ambiguous gap → low-confidence warning (`identify_result_screen.dart:178`)
- Threshold tiers for UI presentation (`tflite_service.dart:309-403`)

However, because of Finding #1 (the normalization bug), the disease classifier
produces **confidently wrong** predictions. A saturated network can output >85%
confidence on arbitrary inputs, so the 60% threshold provides no safety net.

Once the normalization bug is fixed, these existing safeguards should work as intended.
But an additional OOD/abstain mechanism beyond softmax confidence would add robustness.

**Severity:** MEDIUM (HIGH while the normalization bug exists, drops to MEDIUM after fix).

**File:** `MOBILE_APP/lib/services/tflite_service.dart:91-131`

---

### 8. LOW — DEFAULT Quantization Without Representative Dataset

**What:** TFLite conversion in `2_train_phase2.py:423-425` uses:
```python
converter.optimizations = [tf.lite.Optimize.DEFAULT]
```

This applies dynamic-range quantization (weights to int8, activations remain float32
at runtime). This is generally safe and doesn't require a representative dataset.
The `3_evaluate_metrics.py:135-245` comparison function validates Keras vs TFLite
parity with a >2% divergence warning.

Full int8 quantization (which WOULD need a representative dataset) is not used here,
so this is not a significant concern.

**Severity:** LOW — dynamic-range quantization is unlikely to cause meaningful
accuracy loss for MobileNetV3.

**File:** `2_train_phase2.py:423-425`

---

### 9. LOW — Limited Telemetry for Misclassifications

**What:** The app saves scans to Firestore per-user (`users/{uid}/scans/`) and has
a user rating mechanism (`firestore_service.dart:203-222` via `scan_rating_section`
widget). However:

- Feedback data is siloed per-user — there is no aggregated collection for the dev
  team to analyze misclassification patterns.
- Low-confidence or Not_Tomato scans are **not saved** to Firestore
  (`identify_result_screen.dart:172-175`), so the worst false positives leave no trace.
- There is no server-side logging of prediction distributions or confidence histograms.

Without aggregated telemetry, diagnosing which classes produce false positives in the
field is impossible.

**Severity:** LOW — this doesn't cause false positives, but prevents diagnosing them.
Becomes more important after the normalization fix, when fine-tuning threshold values.

**Files:**
- `MOBILE_APP/lib/services/firestore_service.dart:203-222`
- `MOBILE_APP/lib/identify_result_screen.dart:172-175`

---

### 10. INFO — Legacy results.py Uses v3 Model Loader

**What:** `RESULTS/results.py` imports from `SCRIPTS/model_utils.py` (v3 architecture).
It evaluates on `DATA-RAW/field/` without a proper train/test split and does not apply
`preprocess_input` — it sends raw `[0, 255]` arrays to the model
(`results.py:48-50`). If the v3 model had preprocessing baked into the graph, this
would be correct, but it means this script **cannot be used to evaluate the v4 model**
without modification.

Use `3_evaluate_metrics.py` for v4 evaluation instead.

**Severity:** INFO — legacy script, no production impact.

**File:** `RESULTS/results.py:48-50`

---

## Root Cause Chain

```
User captures photo
  → CameraScreen crops to square (OK)
  → TFLiteService._preprocessImageFile() decodes + resizes to 224×224 (OK)
  → BUT: returns raw [0, 255] floats instead of [-1, 1]        ← BUG
  → TFLiteService.runInference() feeds [0, 255] to model
  → Model (trained on [-1, 1]) receives wildly out-of-range input
  → All internal activations saturate
  → Softmax still produces confident-looking distribution
  → App shows "85% confident: Early Blight" on a photo of a shoe  ← FALSE POSITIVE
```

The gatekeeper (Finding #2-3) can't fully prevent this because:
- It's advisory only — users can capture regardless
- Its negative training data coverage is unknown
- No temporal smoothing means transient false positives in viewfinder

---

## Recommended Fix Priority

1. **Fix normalization** in `tflite_service.dart` (Finding 1) — immediate, ~10 lines
2. **Verify gatekeeper negatives** and retrain if needed (Finding 2-3)
3. **Add temporal smoothing** to gatekeeper (Finding 4) — low effort
4. **Add augmentations** for motion blur, shadow, occlusion (Finding 6)
5. **Investigate data leakage** in train/test split (Finding 5)
6. **Add aggregated telemetry** collection (Finding 9)

Fixing #1 alone is expected to eliminate the majority of observed false positives.
