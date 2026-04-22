"""
1_train_phase1_v2.py - Phase 1 warm-up on the public 5-class dataset.

This mirrors the existing Phase 1 pipeline, but swaps the backbone from
MobileNetV3Large to MobileNetV2 so you can train a separate comparison model.

Prerequisites:
    - Public dataset images at DATA-RAW/public/
      with subfolders: Early_Blight, Healthy, Leaf_Miner, Leaf_Mold, Not_Tomato
      (1,000 images each)

Outputs:
    - MODEL/phase1_base_v2.keras
    - MODEL/phase1_base_v2.h5

Usage:
    python 1_train_phase1_v2.py
"""

import os
import random
import shutil

import tensorflow as tf
from tensorflow.keras import layers

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PUBLIC_RAW_DIR = os.path.join(BASE_DIR, "DATA-RAW", "public")
PUBLIC_SPLIT_DIR = os.path.join(BASE_DIR, "DATA-SPLIT", "public_1k")
MODEL_OUTPUT = os.path.join(BASE_DIR, "MODEL", "phase1_base_v2.keras")
MODEL_OUTPUT_H5 = MODEL_OUTPUT.replace(".keras", ".h5")

CLASS_NAMES = ["Early_Blight", "Healthy", "Leaf_Miner", "Leaf_Mold", "Not_Tomato"]

IMG_SIZE = 224
BATCH_SIZE = 32
EPOCHS = 15
SEED = 42
VALID_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp"}


def split_public_dataset():
    """Split the public dataset into 80% train / 20% val."""
    print("\n--- Splitting public dataset (80/20) ---")

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

        for split_name, img_list in [("train", train_imgs), ("val", val_imgs)]:
            dst_dir = os.path.join(PUBLIC_SPLIT_DIR, split_name, class_name)
            os.makedirs(dst_dir, exist_ok=True)
            for img_name in img_list:
                shutil.copy2(
                    os.path.join(src_dir, img_name),
                    os.path.join(dst_dir, img_name),
                )

        total_train += len(train_imgs)
        total_val += len(val_imgs)
        print(f"  {class_name}: {len(train_imgs)} train / {len(val_imgs)} val")

    print(f"  Total: {total_train} train / {total_val} val\n")


def build_phase1_model():
    """Build MobileNetV2 with a frozen base and simple classifier head."""
    base = tf.keras.applications.MobileNetV2(
        input_shape=(IMG_SIZE, IMG_SIZE, 3),
        include_top=False,
        weights="imagenet",
    )
    base.trainable = False

    inputs = tf.keras.Input(shape=(IMG_SIZE, IMG_SIZE, 3))
    x = base(inputs)
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.Dropout(0.3)(x)
    outputs = layers.Dense(5, activation="softmax")(x)

    return tf.keras.Model(inputs, outputs)


def preprocess_ds(images, labels):
    """Apply MobileNetV2 preprocessing: [0, 255] -> [-1, 1]."""
    images = tf.keras.applications.mobilenet_v2.preprocess_input(images)
    return images, labels


def train():
    """Load data, build the model, and train Phase 1."""
    split_public_dataset()

    train_ds = tf.keras.utils.image_dataset_from_directory(
        os.path.join(PUBLIC_SPLIT_DIR, "train"),
        image_size=(IMG_SIZE, IMG_SIZE),
        crop_to_aspect_ratio=True,
        batch_size=BATCH_SIZE,
        label_mode="categorical",
        seed=SEED,
        shuffle=True,
    )

    val_ds = tf.keras.utils.image_dataset_from_directory(
        os.path.join(PUBLIC_SPLIT_DIR, "val"),
        image_size=(IMG_SIZE, IMG_SIZE),
        crop_to_aspect_ratio=True,
        batch_size=BATCH_SIZE,
        label_mode="categorical",
        seed=SEED,
        shuffle=False,
    )

    print(f"Class names: {train_ds.class_names}")

    autotune = tf.data.AUTOTUNE
    train_ds = train_ds.map(preprocess_ds, num_parallel_calls=autotune).prefetch(autotune)
    val_ds = val_ds.map(preprocess_ds, num_parallel_calls=autotune).prefetch(autotune)

    model = build_phase1_model()
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=1e-3),
        loss=tf.keras.losses.CategoricalCrossentropy(),
        metrics=["accuracy"],
    )
    model.summary()

    os.makedirs(os.path.dirname(MODEL_OUTPUT), exist_ok=True)

    h5_checkpoint = MODEL_OUTPUT_H5
    callbacks = [
        tf.keras.callbacks.ModelCheckpoint(
            h5_checkpoint,
            monitor="val_accuracy",
            save_best_only=True,
            verbose=1,
        ),
    ]

    history = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=EPOCHS,
        callbacks=callbacks,
    )

    best_model = tf.keras.models.load_model(h5_checkpoint, compile=False)
    try:
        best_model.save(MODEL_OUTPUT)
        print(f"\nPhase 1 best model saved to: {MODEL_OUTPUT}")
    except ValueError as exc:
        if "not supported with the native Keras format" not in str(exc):
            raise
        print(
            "\nNative .keras export is not supported in this environment. "
            f"Keeping the compatible H5 checkpoint instead: {MODEL_OUTPUT_H5}"
        )

    final_train_acc = history.history["accuracy"][-1]
    final_val_acc = history.history["val_accuracy"][-1]
    print(f"Final train accuracy: {final_train_acc:.4f}")
    print(f"Final val accuracy:   {final_val_acc:.4f}")


if __name__ == "__main__":
    train()
