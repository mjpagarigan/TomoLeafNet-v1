"""
1_train_phase1.py — Phase 1: Warm-Up on Public 5-Class Dataset

Trains a MobileNetV3Large base model (frozen) on the public 5-class dataset
with an 80/20 train/val split. This produces a warm-up checkpoint that
Phase 2 fine-tunes on real field data.

Prerequisites:
    - Public dataset images at DATA-RAW/public/
      with subfolders: Early_Blight, Healthy, Leaf_Miner, Leaf_Mold, Not_Tomato
      (1,000 images each)

Usage:
    python 1_train_phase1.py
"""

import os
import shutil
import random

import tensorflow as tf
from tensorflow.keras import layers

# ── Paths ─────────────────────────────────────────────────────────────
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PUBLIC_RAW_DIR = os.path.join(BASE_DIR, "DATA-RAW", "public")
PUBLIC_SPLIT_DIR = os.path.join(BASE_DIR, "DATA-SPLIT", "public_1k")
MODEL_OUTPUT = os.path.join(BASE_DIR, "MODEL", "phase1_base.keras")
MODEL_OUTPUT_H5 = MODEL_OUTPUT.replace(".keras", ".h5")

CLASS_NAMES = ["Early_Blight", "Healthy", "Leaf_Miner", "Leaf_Mold", "Not_Tomato"]

IMG_SIZE = 224
BATCH_SIZE = 32
EPOCHS = 15
SEED = 42
VALID_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp"}


# ── Step 1: Split public dataset 80/20 ───────────────────────────────

def split_public_dataset():
    """Split public dataset into 80% train / 20% val."""
    print("\n── Splitting public dataset (80/20) ──")

    if os.path.exists(PUBLIC_SPLIT_DIR):
        shutil.rmtree(PUBLIC_SPLIT_DIR)

    total_train = 0
    total_val = 0

    for class_name in CLASS_NAMES:
        src_dir = os.path.join(PUBLIC_RAW_DIR, class_name)
        if not os.path.isdir(src_dir):
            print(f"  WARNING: {src_dir} not found, skipping")
            continue

        images = [
            f for f in os.listdir(src_dir)
            if os.path.splitext(f)[1].lower() in VALID_EXTENSIONS
        ]
        random.Random(SEED).shuffle(images)

        split_idx = int(len(images) * 0.8)
        train_imgs = images[:split_idx]
        val_imgs = images[split_idx:]

        # Create dirs and copy
        for split_name, img_list in [("train", train_imgs), ("val", val_imgs)]:
            dst_dir = os.path.join(PUBLIC_SPLIT_DIR, split_name, class_name)
            os.makedirs(dst_dir, exist_ok=True)
            for img in img_list:
                shutil.copy2(
                    os.path.join(src_dir, img),
                    os.path.join(dst_dir, img),
                )

        total_train += len(train_imgs)
        total_val += len(val_imgs)
        print(f"  {class_name}: {len(train_imgs)} train / {len(val_imgs)} val")

    print(f"  Total: {total_train} train / {total_val} val\n")


# ── Step 2: Build model ──────────────────────────────────────────────

def build_phase1_model():
    """Build MobileNetV3Large with frozen base + simple classification head.

    NOTE: preprocess_input is NOT embedded in the model graph. Instead,
    preprocessing is applied to the dataset pipeline (see preprocess_ds())
    and in the Flutter app's tflite_service.dart. This ensures the TFLite
    model receives [-1, 1] normalized inputs directly, avoiding any
    ambiguity about whether TFLite conversion preserves the preprocessing
    layer.
    """
    base = tf.keras.applications.MobileNetV3Large(
        input_shape=(IMG_SIZE, IMG_SIZE, 3),
        include_top=False,
        weights="imagenet",
    )
    base.trainable = False  # Freeze base for Phase 1

    inputs = tf.keras.Input(shape=(IMG_SIZE, IMG_SIZE, 3))
    x = base(inputs, training=False)
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.Dropout(0.3)(x)
    out = layers.Dense(5, activation="softmax")(x)

    model = tf.keras.Model(inputs, out)
    return model


def preprocess_ds(images, labels):
    """Apply MobileNetV3 preprocessing: [0, 255] -> [-1, 1]."""
    images = tf.keras.applications.mobilenet_v3.preprocess_input(images)
    return images, labels


# ── Step 3: Train ─────────────────────────────────────────────────────

def train():
    """Load data, build model, and train Phase 1."""

    # Split public dataset first
    split_public_dataset()

    # Load datasets
    train_ds = tf.keras.utils.image_dataset_from_directory(
        os.path.join(PUBLIC_SPLIT_DIR, "train"),
        image_size=(IMG_SIZE, IMG_SIZE),
        batch_size=BATCH_SIZE,
        label_mode="categorical",
        seed=SEED,
        shuffle=True,
    )

    val_ds = tf.keras.utils.image_dataset_from_directory(
        os.path.join(PUBLIC_SPLIT_DIR, "val"),
        image_size=(IMG_SIZE, IMG_SIZE),
        batch_size=BATCH_SIZE,
        label_mode="categorical",
        seed=SEED,
        shuffle=False,
    )

    # Print class names (should be alphabetical)
    print(f"Class names: {train_ds.class_names}")

    # Apply MobileNetV3 preprocessing: [0, 255] -> [-1, 1]
    AUTOTUNE = tf.data.AUTOTUNE
    train_ds = train_ds.map(preprocess_ds, num_parallel_calls=AUTOTUNE).prefetch(AUTOTUNE)
    val_ds = val_ds.map(preprocess_ds, num_parallel_calls=AUTOTUNE).prefetch(AUTOTUNE)

    # Build and compile model
    model = build_phase1_model()
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=1e-3),
        loss=tf.keras.losses.CategoricalCrossentropy(),
        metrics=["accuracy"],
    )
    model.summary()

    # Ensure output directory exists
    os.makedirs(os.path.dirname(MODEL_OUTPUT), exist_ok=True)

    # Train with checkpoint saving best model
    # Use .h5 for checkpoints to avoid Keras 3 save_model options bug,
    # then convert to .keras at the end.
    h5_checkpoint = MODEL_OUTPUT_H5
    callbacks = [
        tf.keras.callbacks.ModelCheckpoint(
            h5_checkpoint, monitor="val_accuracy", save_best_only=True, verbose=1,
        ),
    ]

    history = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=EPOCHS,
        callbacks=callbacks,
    )

    # Try to convert the best .h5 checkpoint to .keras. Some TensorFlow/Keras
    # combinations still pass an unsupported `options=` argument when saving
    # the native .keras format, so keep the .h5 checkpoint as a supported
    # fallback for Phase 2.
    best_model = tf.keras.models.load_model(h5_checkpoint)
    try:
        best_model.save(MODEL_OUTPUT)
        print(f"\nPhase 1 best model saved to: {MODEL_OUTPUT}")
    except ValueError as e:
        if "not supported with the native Keras format" not in str(e):
            raise
        print(
            "\nNative .keras export is not supported in this environment. "
            f"Keeping the compatible H5 checkpoint instead: {MODEL_OUTPUT_H5}"
        )

    # Print final metrics
    final_train_acc = history.history["accuracy"][-1]
    final_val_acc = history.history["val_accuracy"][-1]
    print(f"Final train accuracy: {final_train_acc:.4f}")
    print(f"Final val accuracy:   {final_val_acc:.4f}")


if __name__ == "__main__":
    train()
