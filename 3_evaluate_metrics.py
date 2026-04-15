"""
3_evaluate_metrics.py — Evaluation on Unseen Field Test Set

Loads the final fine-tuned model and evaluates on the held-out test split
(real field images only, no synthetic augmentation).

Prerequisites:
    - Run 0_augment_field_dataset.py first (creates DATA-SPLIT/target_field/test/)
    - Run 2_train_phase2.py first (creates MODEL/tomoleafnet_v4_final.keras)

Outputs:
    - RESULTS/Confusion_Matrix.png
    - Classification report + per-class accuracy printed to console

Usage:
    python 3_evaluate_metrics.py
"""

import os

import matplotlib.pyplot as plt
import numpy as np
import seaborn as sns
import tensorflow as tf
from sklearn.metrics import classification_report, confusion_matrix

# ── Paths ─────────────────────────────────────────────────────────────
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
TEST_DIR = os.path.join(BASE_DIR, "DATA-SPLIT", "target_field", "test")
MODEL_PATH = os.path.join(BASE_DIR, "MODEL", "tomoleafnet_v4_final.keras")
TFLITE_PATH = os.path.join(BASE_DIR, "MODEL", "tomoleafnet_v4.tflite")
RESULTS_DIR = os.path.join(BASE_DIR, "RESULTS")
CM_PATH = os.path.join(RESULTS_DIR, "Confusion_Matrix.png")

IMG_SIZE = 224
BATCH_SIZE = 32

CLASS_NAMES = ["Early_Blight", "Healthy", "Leaf_Miner", "Leaf_Mold", "Not_Tomato"]


def evaluate():
    """Load model and evaluate on the unseen test set."""

    print("=" * 60)
    print("  TomoLeafNet v4 — Evaluation on Unseen Test Set")
    print("=" * 60)

    # ── Load test dataset ─────────────────────────────────────────────
    print(f"\nTest data: {TEST_DIR}")
    test_ds = tf.keras.utils.image_dataset_from_directory(
        TEST_DIR,
        image_size=(IMG_SIZE, IMG_SIZE),
        batch_size=BATCH_SIZE,
        label_mode="categorical",
        shuffle=False,  # IMPORTANT: keep order for correct label alignment
    )

    print(f"Class names (from directory): {test_ds.class_names}")
    assert test_ds.class_names == CLASS_NAMES, (
        f"Class order mismatch! Expected {CLASS_NAMES}, got {test_ds.class_names}"
    )

    # Apply MobileNetV3 preprocessing: [0, 255] -> [-1, 1]
    def preprocess_ds(images, labels):
        images = tf.keras.applications.mobilenet_v3.preprocess_input(images)
        return images, labels

    test_ds = test_ds.map(preprocess_ds)

    # ── Load model ────────────────────────────────────────────────────
    print(f"\nLoading model: {MODEL_PATH}")
    model = tf.keras.models.load_model(MODEL_PATH, compile=False)

    # ── Predict ───────────────────────────────────────────────────────
    print("\nRunning predictions on test set...")
    y_true_list = []
    y_pred_list = []

    for images, labels in test_ds:
        preds = model.predict(images, verbose=0)
        y_pred_list.append(np.argmax(preds, axis=1))
        y_true_list.append(np.argmax(labels.numpy(), axis=1))

    y_true = np.concatenate(y_true_list)
    y_pred = np.concatenate(y_pred_list)

    # ── Classification Report ─────────────────────────────────────────
    print("\n" + "=" * 60)
    print("  CLASSIFICATION REPORT")
    print("=" * 60)
    print(
        classification_report(
            y_true, y_pred, target_names=CLASS_NAMES, digits=4
        )
    )

    # ── Per-Class Accuracy ────────────────────────────────────────────
    print("\n--- PER-CLASS ACCURACY ---")
    for i, class_name in enumerate(CLASS_NAMES):
        class_mask = y_true == i
        if class_mask.sum() > 0:
            class_acc = np.mean(y_pred[class_mask] == y_true[class_mask])
            print(f"  {class_name}: {class_acc:.2%} ({class_mask.sum()} samples)")
        else:
            print(f"  {class_name}: N/A (0 samples)")

    overall_acc = np.mean(y_pred == y_true)
    print(f"\n  Overall Accuracy: {overall_acc:.2%} ({len(y_true)} samples)")

    # ── Confusion Matrix ──────────────────────────────────────────────
    os.makedirs(RESULTS_DIR, exist_ok=True)

    cm = confusion_matrix(y_true, y_pred)
    fig, ax = plt.subplots(figsize=(8, 7))
    sns.heatmap(
        cm,
        annot=True,
        fmt="d",
        cmap="Greens",
        xticklabels=CLASS_NAMES,
        yticklabels=CLASS_NAMES,
        ax=ax,
    )
    ax.set_xlabel("Predicted", fontsize=12)
    ax.set_ylabel("Actual", fontsize=12)
    ax.set_title("TomoLeafNet v4 — Confusion Matrix (Field Test Set)", fontsize=14)
    plt.xticks(rotation=45, ha="right")
    plt.yticks(rotation=0)
    plt.tight_layout()
    plt.savefig(CM_PATH, dpi=150)
    print(f"\nConfusion matrix saved to: {CM_PATH}")
    print("=" * 60)


def compare_tflite():
    """Compare Keras vs TFLite model accuracy on the test set.

    Detects preprocessing mismatch or quantization degradation by running
    both models on the same images and reporting any divergence.
    """
    if not os.path.exists(TFLITE_PATH):
        print(f"\n[SKIP] TFLite model not found at {TFLITE_PATH}")
        print("  Run 'python resume_stage3.py --export' to generate it.\n")
        return

    print("\n" + "=" * 60)
    print("  KERAS vs TFLITE COMPARISON")
    print("=" * 60)

    # Load Keras model
    keras_model = tf.keras.models.load_model(MODEL_PATH, compile=False)

    # Load TFLite model
    interpreter = tf.lite.Interpreter(model_path=TFLITE_PATH)
    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    tflite_input_shape = input_details[0]["shape"]
    tflite_output_shape = output_details[0]["shape"]
    print(f"  TFLite input shape:  {tflite_input_shape}")
    print(f"  TFLite output shape: {tflite_output_shape}")

    if tflite_output_shape[-1] != len(CLASS_NAMES):
        print(f"\n  [ERROR] TFLite outputs {tflite_output_shape[-1]} classes "
              f"but expected {len(CLASS_NAMES)}!")
        print("  The bundled TFLite is from an older model. Re-export needed.")
        return

    # Load test dataset with MobileNetV3 preprocessing
    def preprocess_cmp(images, labels):
        images = tf.keras.applications.mobilenet_v3.preprocess_input(images)
        return images, labels

    test_ds = tf.keras.utils.image_dataset_from_directory(
        TEST_DIR,
        image_size=(IMG_SIZE, IMG_SIZE),
        batch_size=1,
        label_mode="categorical",
        shuffle=False,
    ).map(preprocess_cmp)

    keras_preds = []
    tflite_preds = []
    y_true = []
    match_count = 0
    total = 0

    for images, labels in test_ds:
        # Keras prediction
        keras_out = keras_model.predict(images, verbose=0)
        keras_cls = np.argmax(keras_out[0])
        keras_preds.append(keras_cls)

        # TFLite prediction (same raw [0,255] input)
        input_data = images.numpy().astype(np.float32)
        interpreter.set_tensor(input_details[0]["index"], input_data)
        interpreter.invoke()
        tflite_out = interpreter.get_tensor(output_details[0]["index"])
        tflite_cls = np.argmax(tflite_out[0])
        tflite_preds.append(tflite_cls)

        true_cls = np.argmax(labels.numpy()[0])
        y_true.append(true_cls)

        if keras_cls == tflite_cls:
            match_count += 1
        total += 1

    keras_preds = np.array(keras_preds)
    tflite_preds = np.array(tflite_preds)
    y_true = np.array(y_true)

    keras_acc = np.mean(keras_preds == y_true)
    tflite_acc = np.mean(tflite_preds == y_true)
    agreement = match_count / total

    print(f"\n  Keras accuracy:     {keras_acc:.2%}")
    print(f"  TFLite accuracy:    {tflite_acc:.2%}")
    print(f"  Accuracy delta:     {abs(keras_acc - tflite_acc):.2%}")
    print(f"  Prediction agreement: {agreement:.2%} ({match_count}/{total})")

    if abs(keras_acc - tflite_acc) > 0.02:
        print("\n  [WARNING] Accuracy delta > 2% — possible quantization issue")
        print("  Consider using float16 quantization instead of DEFAULT.")
    elif abs(keras_acc - tflite_acc) > 0.05:
        print("\n  [CRITICAL] Accuracy delta > 5% — likely preprocessing mismatch!")
        print("  The TFLite model may have lost the preprocess_input layer.")
        print("  Fix: add explicit normalization in Flutter (pixel/127.5 - 1.0)")
    else:
        print("\n  [OK] TFLite accuracy is within acceptable range.")

    # Per-class TFLite accuracy
    print("\n  --- PER-CLASS TFLITE ACCURACY ---")
    for i, class_name in enumerate(CLASS_NAMES):
        mask = y_true == i
        if mask.sum() > 0:
            acc = np.mean(tflite_preds[mask] == y_true[mask])
            keras_class_acc = np.mean(keras_preds[mask] == y_true[mask])
            delta = acc - keras_class_acc
            flag = " <-- DEGRADED" if delta < -0.05 else ""
            print(f"    {class_name}: Keras {keras_class_acc:.2%} -> "
                  f"TFLite {acc:.2%} (delta {delta:+.2%}){flag}")

    print("=" * 60)


if __name__ == "__main__":
    evaluate()
    compare_tflite()
