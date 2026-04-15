"""
resume_stage3.py — Resume Stage 3 training from the best checkpoint.

Loads MODEL/tomoleafnet_v4_final.keras (87% val accuracy checkpoint),
unfreezes all layers, and continues training with the same Stage 3
settings (lr=1e-5, EarlyStopping patience=12).

After training, exports TFLite and plots curves.

Usage:
    python resume_stage3.py          # Resume training
    python resume_stage3.py --export  # Skip training, just export TFLite
"""

import math
import os
import sys

import tensorflow as tf
from tensorflow.keras import layers

# ── Paths ─────────────────────────────────────────────────────────────
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
FIELD_DATA_DIR = os.path.join(BASE_DIR, "DATA-SPLIT", "target_field")
FINAL_KERAS = os.path.join(BASE_DIR, "MODEL", "tomoleafnet_v4_final.keras")
FINAL_TFLITE = os.path.join(BASE_DIR, "MODEL", "tomoleafnet_v4.tflite")
RESULTS_DIR = os.path.join(BASE_DIR, "RESULTS")
CSV_LOG_PATH = os.path.join(RESULTS_DIR, "Resume_History.csv")

IMG_SIZE = 224
BATCH_SIZE = 32
SEED = 42
RESUME_EPOCHS = 30  # Additional epochs to train
MIXUP_ALPHA = 0.1


# ── Custom LR schedule (needed for model loading) ───────────────────

@tf.keras.utils.register_keras_serializable()
class WarmupCosineDecay(tf.keras.optimizers.schedules.LearningRateSchedule):
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


# ── Augmentation ─────────────────────────────────────────────────────
augment = tf.keras.Sequential([
    layers.RandomFlip("horizontal_and_vertical"),
    layers.RandomRotation(0.25),
    layers.RandomZoom((-0.3, 0.15)),
    layers.RandomTranslation(0.2, 0.2),
    layers.RandomContrast(0.3),
    layers.RandomBrightness(0.3),
    layers.GaussianNoise(0.06),
])


def mixup(images, labels, alpha=MIXUP_ALPHA):
    batch_size = tf.shape(images)[0]
    lam = tf.random.gamma(shape=[batch_size, 1, 1, 1], alpha=alpha)
    lam = tf.maximum(lam, 1.0 - lam)
    lam_labels = tf.reshape(lam, [batch_size, 1])
    indices = tf.random.shuffle(tf.range(batch_size))
    shuffled_images = tf.gather(images, indices)
    shuffled_labels = tf.gather(labels, indices)
    mixed_images = lam * images + (1.0 - lam) * shuffled_images
    mixed_labels = lam_labels * labels + (1.0 - lam_labels) * shuffled_labels
    return mixed_images, mixed_labels


def augment_and_mixup(images, labels):
    """Apply spatial augmentation, Mixup, then MobileNetV3 preprocessing."""
    images = augment(images, training=True)
    images, labels = mixup(images, labels)
    # Normalize [0, 255] -> [-1, 1] after augmentation
    images = tf.keras.applications.mobilenet_v3.preprocess_input(images)
    return images, labels


def preprocess_ds(images, labels):
    """Apply MobileNetV3 preprocessing: [0, 255] -> [-1, 1]."""
    images = tf.keras.applications.mobilenet_v3.preprocess_input(images)
    return images, labels


def compute_class_weights(train_dir, class_names):
    counts = {}
    for i, cls in enumerate(class_names):
        cls_dir = os.path.join(train_dir, cls)
        n = len([f for f in os.listdir(cls_dir) if not f.startswith(".")])
        counts[i] = n
    total = sum(counts.values())
    n_classes = len(counts)
    weights = {}
    for idx, count in counts.items():
        weights[idx] = total / (n_classes * count)
    return weights


def export_tflite():
    """Export the best .keras checkpoint to TFLite."""
    print(f"\nLoading best checkpoint: {FINAL_KERAS}")
    model = tf.keras.models.load_model(
        FINAL_KERAS,
        custom_objects={"WarmupCosineDecay": WarmupCosineDecay},
    )

    print("Converting to TFLite...")
    # Save to SavedModel in system temp dir to avoid OneDrive file locks
    import shutil
    import tempfile
    saved_model_dir = os.path.join(tempfile.gettempdir(), "tomoleafnet_saved_model")
    if os.path.exists(saved_model_dir):
        shutil.rmtree(saved_model_dir)
    model.export(saved_model_dir)

    converter = tf.lite.TFLiteConverter.from_saved_model(saved_model_dir)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = converter.convert()

    with open(FINAL_TFLITE, "wb") as f:
        f.write(tflite_model)

    shutil.rmtree(saved_model_dir, ignore_errors=True)

    size_mb = os.path.getsize(FINAL_TFLITE) / (1024 * 1024)
    print(f"TFLite model saved to: {FINAL_TFLITE} ({size_mb:.2f} MB)")


def resume_training():
    """Load checkpoint and continue Stage 3 training."""

    # ── Load datasets ────────────────────────────────────────────────
    train_ds = tf.keras.utils.image_dataset_from_directory(
        os.path.join(FIELD_DATA_DIR, "train"),
        image_size=(IMG_SIZE, IMG_SIZE),
        batch_size=BATCH_SIZE,
        label_mode="categorical",
        seed=SEED,
        shuffle=True,
    )

    val_ds = tf.keras.utils.image_dataset_from_directory(
        os.path.join(FIELD_DATA_DIR, "val"),
        image_size=(IMG_SIZE, IMG_SIZE),
        batch_size=BATCH_SIZE,
        label_mode="categorical",
        seed=SEED,
        shuffle=False,
    )

    class_names = train_ds.class_names
    print(f"Class names: {class_names}")

    class_weights = compute_class_weights(
        os.path.join(FIELD_DATA_DIR, "train"), class_names
    )

    AUTOTUNE = tf.data.AUTOTUNE
    train_ds_aug = train_ds.map(
        augment_and_mixup, num_parallel_calls=AUTOTUNE
    ).prefetch(AUTOTUNE)
    val_ds = val_ds.map(preprocess_ds, num_parallel_calls=AUTOTUNE).prefetch(AUTOTUNE)

    steps_per_epoch = len(train_ds)

    # ── Load best checkpoint ─────────────────────────────────────────
    print(f"\nLoading checkpoint: {FINAL_KERAS}")
    model = tf.keras.models.load_model(
        FINAL_KERAS,
        custom_objects={"WarmupCosineDecay": WarmupCosineDecay},
    )

    # Ensure all layers are trainable (Stage 3 = full unfreeze)
    for layer in model.layers:
        layer.trainable = True
        if isinstance(layer, tf.keras.Model):
            for sub_layer in layer.layers:
                sub_layer.trainable = True

    # Quick validation to confirm starting accuracy
    print("\nValidating checkpoint accuracy...")
    val_loss, val_acc = model.evaluate(val_ds, verbose=1)
    print(f"Checkpoint val accuracy: {val_acc:.4f}")

    # ── Recompile with fresh cosine decay LR ─────────────────────────
    total_steps = steps_per_epoch * RESUME_EPOCHS
    warmup_steps = steps_per_epoch * 2  # 2-epoch warmup

    lr_schedule = WarmupCosineDecay(
        base_lr=1e-5,
        total_steps=total_steps,
        warmup_steps=warmup_steps,
        min_lr=1e-7,
    )

    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=lr_schedule),
        loss=tf.keras.losses.CategoricalCrossentropy(),
        metrics=["accuracy"],
    )

    # ── Train ────────────────────────────────────────────────────────
    os.makedirs(RESULTS_DIR, exist_ok=True)
    callbacks = [
        tf.keras.callbacks.EarlyStopping(
            monitor="val_loss", patience=12, restore_best_weights=True, verbose=1,
        ),
        tf.keras.callbacks.ModelCheckpoint(
            FINAL_KERAS, monitor="val_accuracy", save_best_only=True, verbose=1,
        ),
        tf.keras.callbacks.CSVLogger(CSV_LOG_PATH, append=False),
    ]

    print(f"\nResuming training for up to {RESUME_EPOCHS} epochs...")
    history = model.fit(
        train_ds_aug,
        validation_data=val_ds,
        epochs=RESUME_EPOCHS,
        callbacks=callbacks,
        class_weight=class_weights,
    )

    # ── Results ──────────────────────────────────────────────────────
    best_val_acc = max(history.history["val_accuracy"])
    print(f"\nBest val accuracy this run: {best_val_acc:.4f}")
    print(f"Final val accuracy:        {history.history['val_accuracy'][-1]:.4f}")

    # ── Export TFLite ────────────────────────────────────────────────
    export_tflite()


if __name__ == "__main__":
    if "--export" in sys.argv:
        export_tflite()
    else:
        resume_training()
