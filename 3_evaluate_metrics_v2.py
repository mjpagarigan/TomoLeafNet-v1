"""
3_evaluate_metrics_v2.py - Evaluate the MobileNetV2 field model.

This mirrors the existing v5 evaluation flow, but targets the separate
MobileNetV2 training outputs and uses MobileNetV2 preprocessing.

Prerequisites:
    - Run 0_augment_field_dataset.py first
    - Run 2_train_phase2_v2.py first

Outputs:
    - RESULTS/Confusion_Matrix_v2.png
    - Classification report and per-class accuracy in the console

Usage:
    python 3_evaluate_metrics_v2.py
"""

import os

import matplotlib.pyplot as plt
import numpy as np
import seaborn as sns
import tensorflow as tf
from sklearn.metrics import classification_report, confusion_matrix
from tensorflow.keras import layers

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
TEST_DIR = os.path.join(BASE_DIR, "DATA-SPLIT", "target_field", "test")
MODEL_PATH = os.path.join(BASE_DIR, "MODEL", "tomoleafnet_v2_final.keras")
MODEL_PATH_H5 = MODEL_PATH.replace(".keras", ".h5")
TFLITE_PATH = os.path.join(BASE_DIR, "MODEL", "tomoleafnet_v2.tflite")
RESULTS_DIR = os.path.join(BASE_DIR, "RESULTS")
CM_PATH = os.path.join(RESULTS_DIR, "Confusion_Matrix_v2.png")

IMG_SIZE = 224
BATCH_SIZE = 32

CLASS_NAMES = ["Early_Blight", "Healthy", "Leaf_Miner", "Leaf_Mold", "Not_Tomato"]


def resolve_model_path():
    """Prefer the native Keras export but allow the H5 fallback."""
    return MODEL_PATH if os.path.exists(MODEL_PATH) else MODEL_PATH_H5


def build_classifier_model():
    """Build the inference classifier used for weight-loading fallback."""
    base = tf.keras.applications.MobileNetV2(
        input_shape=(IMG_SIZE, IMG_SIZE, 3),
        include_top=False,
        weights=None,
    )
    inputs = tf.keras.Input(shape=(IMG_SIZE, IMG_SIZE, 3))
    x = base(inputs)
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.Dropout(0.3)(x)
    outputs = layers.Dense(len(CLASS_NAMES), activation="softmax")(x)
    return tf.keras.Model(inputs, outputs)


def load_classifier_for_inference():
    """Load the best classifier, falling back to H5 weight loading if needed."""
    model_path = resolve_model_path()

    try:
        model = tf.keras.models.load_model(model_path, compile=False)
        print(f"Loaded model via full-model deserialization: {model_path}")
        return model
    except Exception as exc:
        if not model_path.endswith(".h5") and os.path.exists(MODEL_PATH_H5):
            model_path = MODEL_PATH_H5
        elif not model_path.endswith(".h5"):
            raise

        model = build_classifier_model()
        model.load_weights(model_path, by_name=True, skip_mismatch=False)
        print(
            f"Loaded model via H5 weight fallback: {model_path} "
            f"(full-model load failed: {type(exc).__name__})"
        )
        return model


def build_dataset(data_dir, batch_size):
    """Match the mobile preprocessing geometry before normalization."""
    ds = tf.keras.utils.image_dataset_from_directory(
        data_dir,
        image_size=(IMG_SIZE, IMG_SIZE),
        crop_to_aspect_ratio=True,
        batch_size=batch_size,
        label_mode="categorical",
        shuffle=False,
    )

    def preprocess_ds(images, labels):
        images = tf.keras.applications.mobilenet_v2.preprocess_input(images)
        return images, labels

    return ds.map(preprocess_ds)


def evaluate():
    """Load the model and evaluate on the unseen test set."""
    print("=" * 60)
    print("  TomoLeafNet v2 - Evaluation on Unseen Test Set")
    print("=" * 60)

    print(f"\nTest data: {TEST_DIR}")
    test_ds_raw = tf.keras.utils.image_dataset_from_directory(
        TEST_DIR,
        image_size=(IMG_SIZE, IMG_SIZE),
        crop_to_aspect_ratio=True,
        batch_size=BATCH_SIZE,
        label_mode="categorical",
        shuffle=False,
    )

    print(f"Class names (from directory): {test_ds_raw.class_names}")
    assert test_ds_raw.class_names == CLASS_NAMES, (
        f"Class order mismatch! Expected {CLASS_NAMES}, got {test_ds_raw.class_names}"
    )

    test_ds = build_dataset(TEST_DIR, BATCH_SIZE)

    print("\nLoading model...")
    model = load_classifier_for_inference()

    print("\nRunning predictions on test set...")
    y_true_list = []
    y_pred_list = []

    for images, labels in test_ds:
        preds = model.predict(images, verbose=0)
        y_pred_list.append(np.argmax(preds, axis=1))
        y_true_list.append(np.argmax(labels.numpy(), axis=1))

    y_true = np.concatenate(y_true_list)
    y_pred = np.concatenate(y_pred_list)

    print("\n" + "=" * 60)
    print("  CLASSIFICATION REPORT")
    print("=" * 60)
    print(classification_report(y_true, y_pred, target_names=CLASS_NAMES, digits=4))

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

    os.makedirs(RESULTS_DIR, exist_ok=True)

    cm = confusion_matrix(y_true, y_pred)
    row_sums = cm.sum(axis=1, keepdims=True)
    cm_norm = np.divide(
        cm.astype("float") * 100.0,
        row_sums,
        out=np.zeros_like(cm, dtype=float),
        where=row_sums != 0,
    )

    fig, axes = plt.subplots(1, 2, figsize=(16, 7))

    sns.heatmap(
        cm,
        annot=True,
        fmt="d",
        cmap="Greens",
        xticklabels=CLASS_NAMES,
        yticklabels=CLASS_NAMES,
        ax=axes[0],
        cbar_kws={"label": "Count"},
    )
    axes[0].set_xlabel("Predicted", fontsize=12)
    axes[0].set_ylabel("Actual", fontsize=12)
    axes[0].set_title("Confusion Matrix (Counts)", fontsize=13)

    sns.heatmap(
        cm_norm,
        annot=True,
        fmt=".1f",
        cmap="Greens",
        xticklabels=CLASS_NAMES,
        yticklabels=CLASS_NAMES,
        ax=axes[1],
        vmin=0,
        vmax=100,
        cbar_kws={"label": "Percentage (%)"},
    )
    axes[1].set_xlabel("Predicted", fontsize=12)
    axes[1].set_ylabel("Actual", fontsize=12)
    axes[1].set_title("Confusion Matrix (Normalized %)", fontsize=13)

    fig.suptitle(
        f"TomoLeafNet v2 - Field Test Set (Overall: {overall_acc:.1%})",
        fontsize=15,
        fontweight="bold",
    )
    for axis in axes:
        axis.tick_params(axis="x", rotation=45)
        axis.tick_params(axis="y", rotation=0)
    plt.tight_layout()
    plt.savefig(CM_PATH, dpi=150)
    print(f"\nConfusion matrix saved to: {CM_PATH}")
    print("=" * 60)


def compare_tflite():
    """Compare Keras vs TFLite model accuracy on the test set."""
    if not os.path.exists(TFLITE_PATH):
        print(f"\n[SKIP] TFLite model not found at {TFLITE_PATH}")
        print("  Run 'python 2_train_phase2_v2.py' to generate it.\n")
        return

    print("\n" + "=" * 60)
    print("  KERAS vs TFLITE COMPARISON (v2)")
    print("=" * 60)

    keras_model = load_classifier_for_inference()

    interpreter = tf.lite.Interpreter(model_path=TFLITE_PATH)
    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    tflite_input_shape = input_details[0]["shape"]
    tflite_output_shape = output_details[0]["shape"]
    print(f"  TFLite input shape:  {tflite_input_shape}")
    print(f"  TFLite output shape: {tflite_output_shape}")

    if tflite_output_shape[-1] != len(CLASS_NAMES):
        print(
            f"\n  [ERROR] TFLite outputs {tflite_output_shape[-1]} classes "
            f"but expected {len(CLASS_NAMES)}!"
        )
        print("  The bundled TFLite is from an older model. Re-export needed.")
        return

    test_ds = build_dataset(TEST_DIR, BATCH_SIZE)

    print("  Running Keras predictions (batched)...")
    all_keras_out = keras_model.predict(test_ds, verbose=1)
    keras_preds = np.argmax(all_keras_out, axis=1)

    y_true = np.concatenate([np.argmax(labels.numpy(), axis=1) for _, labels in test_ds])

    print("  Running TFLite predictions...")
    tflite_preds = []
    total = 0
    num_samples = len(y_true)
    test_ds_single = build_dataset(TEST_DIR, 1)

    for images, _ in test_ds_single:
        input_data = images.numpy().astype(np.float32)
        interpreter.set_tensor(input_details[0]["index"], input_data)
        interpreter.invoke()
        tflite_out = interpreter.get_tensor(output_details[0]["index"])
        tflite_preds.append(np.argmax(tflite_out[0]))
        total += 1
        if total % 50 == 0 or total == num_samples:
            print(f"\r  TFLite: {total}/{num_samples}", end="", flush=True)

    print()
    tflite_preds = np.array(tflite_preds)
    match_count = np.sum(keras_preds == tflite_preds)

    keras_acc = np.mean(keras_preds == y_true)
    tflite_acc = np.mean(tflite_preds == y_true)
    delta = abs(keras_acc - tflite_acc)
    agreement = match_count / num_samples

    print(f"\n  Keras accuracy:     {keras_acc:.2%}")
    print(f"  TFLite accuracy:    {tflite_acc:.2%}")
    print(f"  Accuracy delta:     {delta:.2%}")
    print(f"  Prediction agreement: {agreement:.2%} ({match_count}/{num_samples})")

    if delta > 0.05:
        print("\n  [CRITICAL] Accuracy delta > 5% - likely preprocessing mismatch!")
    elif delta > 0.02:
        print("\n  [WARNING] Accuracy delta > 2% - possible quantization issue")
    else:
        print("\n  [OK] TFLite accuracy is within acceptable range.")

    print("\n  --- PER-CLASS TFLITE ACCURACY ---")
    for i, class_name in enumerate(CLASS_NAMES):
        mask = y_true == i
        if mask.sum() > 0:
            acc = np.mean(tflite_preds[mask] == y_true[mask])
            keras_class_acc = np.mean(keras_preds[mask] == y_true[mask])
            class_delta = acc - keras_class_acc
            flag = " <-- DEGRADED" if class_delta < -0.05 else ""
            print(
                f"    {class_name}: Keras {keras_class_acc:.2%} -> "
                f"TFLite {acc:.2%} (delta {class_delta:+.2%}){flag}"
            )

    print("=" * 60)


if __name__ == "__main__":
    evaluate()
    compare_tflite()
