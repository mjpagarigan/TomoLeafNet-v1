"""
4_export_cam_model.py — Export dual-output TFLite model for baked-in CAM.

Loads the trained Keras model and creates a new model with two outputs:
  1. [1, 5]       — class probabilities (softmax)
  2. [1, 7, 7, 5] — per-class CAM maps (conv_features @ dense_weights)

Flutter picks the predicted class's 7x7 CAM and upscales to 224x224.
This replaces 16 occlusion-sensitivity inferences with zero extra cost.

Usage:
    python 4_export_cam_model.py
"""

import math
import os
import shutil
import tempfile

import numpy as np
import tensorflow as tf
import keras


# ── Paths ─────────────────────────────────────────────────────────────
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
KERAS_MODEL = os.path.join(BASE_DIR, "MODEL", "tomoleafnet_v5_final.keras")
KERAS_MODEL_H5 = KERAS_MODEL.replace(".keras", ".h5")
OUTPUT_TFLITE = os.path.join(BASE_DIR, "MODEL", "tomoleafnet_v5_cam.tflite")


# ── Custom LR schedule (needed to load the .keras file) ──────────────

@keras.saving.register_keras_serializable()
class WarmupCosineDecay(keras.optimizers.schedules.LearningRateSchedule):
    def __init__(self, base_lr, total_steps, warmup_steps, min_lr=1e-7):
        super().__init__()
        self.base_lr = base_lr
        self.total_steps = total_steps
        self.warmup_steps = warmup_steps
        self.min_lr = min_lr

    def __call__(self, step):
        step = tf.cast(step, tf.float32)
        warmup_steps = tf.cast(self.warmup_steps, tf.float32)
        total_steps = tf.cast(self.total_steps, tf.float32)
        warmup_lr = self.base_lr * (step / tf.maximum(warmup_steps, 1.0))
        progress = (step - warmup_steps) / tf.maximum(total_steps - warmup_steps, 1.0)
        progress = tf.minimum(progress, 1.0)
        cosine_lr = self.min_lr + 0.5 * (self.base_lr - self.min_lr) * (
            1.0 + tf.cos(math.pi * progress)
        )
        return tf.where(step < warmup_steps, warmup_lr, cosine_lr)

    def get_config(self):
        return {
            "base_lr": self.base_lr,
            "total_steps": self.total_steps,
            "warmup_steps": self.warmup_steps,
            "min_lr": self.min_lr,
        }


def main():
    print("Loading Keras model...")
    model_path = KERAS_MODEL if os.path.exists(KERAS_MODEL) else KERAS_MODEL_H5
    model = keras.models.load_model(model_path, compile=False)
    print(f"Loaded: {model_path}")
    model.summary()

    # ── Identify layers ───────────────────────────────────────────────
    base_model = None
    gap_layer = None
    dropout_layer = None
    dense_layer = None

    for layer in model.layers:
        if hasattr(layer, 'layers') and len(layer.layers) > 10:
            base_model = layer
        if isinstance(layer, keras.layers.GlobalAveragePooling2D):
            gap_layer = layer
        if isinstance(layer, keras.layers.Dropout):
            dropout_layer = layer
        if isinstance(layer, keras.layers.Dense):
            dense_layer = layer

    print(f"Base model: {base_model.name}, output: {base_model.output.shape}")
    print(f"Dense layer: {dense_layer.name}, weights: {dense_layer.get_weights()[0].shape}")

    dense_weights = dense_layer.get_weights()[0]  # [960, 5]
    num_classes = dense_weights.shape[1]
    num_channels = dense_weights.shape[0]

    # ── Build dual-output model by re-wiring through existing layers ──
    # This creates a fresh graph while sharing the same weight objects.
    inp = keras.Input(shape=(224, 224, 3))

    # Forward through existing layers (weights are shared)
    conv_features = base_model(inp)           # [batch, 7, 7, 960]
    gap = gap_layer(conv_features)            # [batch, 960]
    dropped = dropout_layer(gap)              # [batch, 960]
    predictions = dense_layer(dropped)        # [batch, 5]

    # CAM: project conv features to class space using Dense weights.
    # conv_features: [batch, 7, 7, 960], dense_weights: [960, 5]
    # Result: [batch, 7, 7, 5] — one 7x7 heatmap per class.
    # Use a Dense layer with no bias, weights frozen to the classifier weights.
    cam_proj = keras.layers.Dense(
        num_classes,
        use_bias=False,
        trainable=False,
        name="cam_projection",
    )
    # Build by calling it, then set weights
    cam_maps = cam_proj(conv_features)  # [batch, 7, 7, 5]
    cam_proj.set_weights([dense_weights])

    cam_model = keras.Model(inputs=inp, outputs=[predictions, cam_maps])
    print("\nDual-output model:")
    print(f"  Output 0 (predictions): {cam_model.outputs[0].shape}")
    print(f"  Output 1 (cam_maps):    {cam_model.outputs[1].shape}")

    # ── Verify outputs match ──────────────────────────────────────────
    dummy = np.random.rand(1, 224, 224, 3).astype(np.float32) * 255.0
    orig_pred = model.predict(dummy, verbose=0)
    dual_out = cam_model.predict(dummy, verbose=0)
    cam_pred = dual_out[0]
    cam_maps_out = dual_out[1]

    print(f"\nOriginal prediction:  {orig_pred[0]}")
    print(f"CAM model prediction: {cam_pred[0]}")
    print(f"Predictions match: {np.allclose(orig_pred, cam_pred, atol=1e-5)}")
    print(f"CAM maps shape: {cam_maps_out.shape}")

    # Show CAM for predicted class
    pred_class = np.argmax(cam_pred[0])
    cam_for_pred = cam_maps_out[0, :, :, pred_class]
    # ReLU + normalize (will also be done in Flutter)
    cam_for_pred = np.maximum(cam_for_pred, 0)
    cam_max = cam_for_pred.max()
    if cam_max > 0:
        cam_for_pred /= cam_max
    print(f"Predicted class: {pred_class}, CAM range: [{cam_for_pred.min():.3f}, {cam_for_pred.max():.3f}]")

    # ── Export to TFLite ──────────────────────────────────────────────
    print("\nExporting dual-output TFLite model...")

    saved_model_dir = os.path.join(tempfile.gettempdir(), "tomoleafnet_cam_saved")
    if os.path.exists(saved_model_dir):
        shutil.rmtree(saved_model_dir)

    cam_model.export(saved_model_dir)

    converter = tf.lite.TFLiteConverter.from_saved_model(saved_model_dir)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_bytes = converter.convert()

    os.makedirs(os.path.dirname(OUTPUT_TFLITE), exist_ok=True)
    with open(OUTPUT_TFLITE, "wb") as f:
        f.write(tflite_bytes)

    shutil.rmtree(saved_model_dir, ignore_errors=True)

    size_mb = os.path.getsize(OUTPUT_TFLITE) / (1024 * 1024)
    print(f"Saved: {OUTPUT_TFLITE} ({size_mb:.2f} MB)")

    # ── Verify TFLite outputs ─────────────────────────────────────────
    print("\nVerifying TFLite model...")
    interpreter = tf.lite.Interpreter(model_path=OUTPUT_TFLITE)
    interpreter.allocate_tensors()

    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    print(f"Input: {input_details[0]['shape']}, dtype: {input_details[0]['dtype']}")
    for i, od in enumerate(output_details):
        print(f"Output {i}: name={od['name']}, shape={od['shape']}, dtype={od['dtype']}")

    interpreter.set_tensor(input_details[0]['index'], dummy)
    interpreter.invoke()

    out0 = interpreter.get_tensor(output_details[0]['index'])
    out1 = interpreter.get_tensor(output_details[1]['index'])

    # TFLite may reorder outputs — identify by shape
    if out0.shape[-1] == num_classes and len(out0.shape) == 2:
        tflite_pred, tflite_cam = out0, out1
    elif out1.shape[-1] == num_classes and len(out1.shape) == 2:
        tflite_pred, tflite_cam = out1, out0
    else:
        # Check which has 4 dims (cam) vs 2 dims (pred)
        if len(out0.shape) == 4:
            tflite_cam, tflite_pred = out0, out1
        else:
            tflite_pred, tflite_cam = out0, out1

    print(f"\nTFLite prediction shape: {tflite_pred.shape}")
    print(f"TFLite prediction: {tflite_pred[0]}")
    print(f"TFLite CAM shape: {tflite_cam.shape}")
    print(f"Pred match (Keras vs TFLite): {np.allclose(orig_pred, tflite_pred, atol=0.02)}")

    # Store output index mapping for Flutter
    for i, od in enumerate(output_details):
        shape = interpreter.get_tensor(od['index']).shape
        if len(shape) == 2 and shape[-1] == num_classes:
            print(f"\n--> Predictions are output index {i}")
        elif len(shape) == 4:
            print(f"--> CAM maps are output index {i}")

    print("\nDone! Copy MODEL/tomoleafnet_v5_cam.tflite to MOBILE_APP/assets/")


if __name__ == "__main__":
    main()
