"""
evaluate_detector.py — Evaluate the binary tomato-leaf detector.

Reports detector performance on detector_dataset/test with a focus on the
rejection behavior that gates the Flutter camera screen.

Usage:
    python evaluate_detector.py
"""

import os

import matplotlib.pyplot as plt
import numpy as np
import seaborn as sns
import tensorflow as tf
from sklearn.metrics import classification_report, confusion_matrix, precision_recall_fscore_support

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(BASE_DIR, "detector_dataset", "test")
MODEL_PATH = os.path.join(BASE_DIR, "DETECTOR_MODEL", "detector_final.keras")
RESULTS_DIR = os.path.join(BASE_DIR, "RESULTS")
CM_PATH = os.path.join(RESULTS_DIR, "Detector_Confusion_Matrix.png")

CLASS_NAMES = ["not_tomato_leaf", "tomato_leaf"]
IMG_SIZE = (224, 224)
BATCH_SIZE = 32


def preprocess_dataset(images, labels):
    images = tf.keras.applications.mobilenet_v2.preprocess_input(images)
    return images, labels


def main():
    print("=" * 64)
    print("  TomoLeafNet Detector Evaluation")
    print("=" * 64)
    print(f"Test data: {DATA_DIR}")
    print(f"Model:     {MODEL_PATH}")

    test_ds = tf.keras.utils.image_dataset_from_directory(
        DATA_DIR,
        image_size=IMG_SIZE,
        batch_size=BATCH_SIZE,
        label_mode="categorical",
        shuffle=False,
    )

    print(f"Class names: {test_ds.class_names}")
    assert test_ds.class_names == CLASS_NAMES, (
        f"Expected class order {CLASS_NAMES}, got {test_ds.class_names}"
    )

    test_ds = test_ds.map(preprocess_dataset)
    model = tf.keras.models.load_model(MODEL_PATH, compile=False)

    y_true_batches = []
    y_pred_batches = []

    print("\nRunning predictions...")
    for images, labels in test_ds:
        predictions = model.predict(images, verbose=0)
        y_true_batches.append(np.argmax(labels.numpy(), axis=1))
        y_pred_batches.append(np.argmax(predictions, axis=1))

    y_true = np.concatenate(y_true_batches)
    y_pred = np.concatenate(y_pred_batches)

    cm = confusion_matrix(y_true, y_pred, labels=[0, 1])
    report = classification_report(
        y_true,
        y_pred,
        target_names=CLASS_NAMES,
        digits=4,
        zero_division=0,
    )
    precision, recall, f1, _ = precision_recall_fscore_support(
        y_true,
        y_pred,
        labels=[0, 1],
        zero_division=0,
    )

    total = cm.sum()
    overall_accuracy = np.trace(cm) / total if total else 0.0
    false_positive_rate = cm[0, 1] / cm[0].sum() if cm[0].sum() else 0.0
    false_negative_rate = cm[1, 0] / cm[1].sum() if cm[1].sum() else 0.0

    print("\nClassification report")
    print(report)

    print("Confusion matrix")
    print(cm)

    print("\nSummary metrics")
    print(f"Overall accuracy           : {overall_accuracy:.2%}")
    print(f"not_tomato_leaf precision  : {precision[0]:.2%}")
    print(f"not_tomato_leaf recall     : {recall[0]:.2%}")
    print(f"not_tomato_leaf F1         : {f1[0]:.2%}")
    print(f"tomato_leaf precision      : {precision[1]:.2%}")
    print(f"tomato_leaf recall         : {recall[1]:.2%}")
    print(f"tomato_leaf F1             : {f1[1]:.2%}")
    print(f"False positive rate        : {false_positive_rate:.2%}")
    print(f"False negative rate        : {false_negative_rate:.2%}")

    print("\nBenchmark check")
    print(f"Overall >= 92%             : {'PASS' if overall_accuracy >= 0.92 else 'FAIL'}")
    print(f"Tomato recall >= 90%       : {'PASS' if recall[1] >= 0.90 else 'FAIL'}")
    print(f"Not-tomato precision >=95% : {'PASS' if precision[0] >= 0.95 else 'FAIL'}")

    os.makedirs(RESULTS_DIR, exist_ok=True)
    figure, axis = plt.subplots(figsize=(6, 5))
    sns.heatmap(
        cm,
        annot=True,
        fmt="d",
        cmap="Reds",
        xticklabels=CLASS_NAMES,
        yticklabels=CLASS_NAMES,
        ax=axis,
    )
    axis.set_xlabel("Predicted")
    axis.set_ylabel("Actual")
    axis.set_title("Detector Confusion Matrix")
    plt.tight_layout()
    plt.savefig(CM_PATH, dpi=150)

    print(f"\nConfusion matrix saved to: {CM_PATH}")
    print("=" * 64)


if __name__ == "__main__":
    main()
