"""
2_train_phase2.py — Phase 2: Fine-Tuning on Field Dataset (Improved v4)

Loads the Phase 1 warm-up model and fine-tunes MobileNetV3Large on the real
field dataset using progressive unfreezing across 3 stages.

Improvements over v3:
  - Fixed: vertical flip removed (leaves have natural orientation)
  - Added: motion blur, random shadow, random erasing augmentations
    to better match real-world Philippine field capture conditions
  - Mixup alpha 0.1 (less training noise)
  - 3-stage progressive unfreeze: last 30 → last 60 → all layers
  - Stage 1: 20 epochs for stabilization
  - Total epochs: 85 (20 + 20 + 45)

Prerequisites:
    - Run 0_augment_field_dataset.py first (creates DATA-SPLIT/target_field/)
    - Run 1_train_phase1.py first (creates MODEL/phase1_base.keras)

Outputs:
    - MODEL/tomoleafnet_v4_final.keras
    - MODEL/tomoleafnet_v4.tflite (DEFAULT optimization)
    - RESULTS/Phase2_Curves.png

Usage:
    python 2_train_phase2.py
"""

import math
import os

import matplotlib.pyplot as plt
import tensorflow as tf
from tensorflow.keras import layers

# ── Paths ─────────────────────────────────────────────────────────────
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
FIELD_DATA_DIR = os.path.join(BASE_DIR, "DATA-SPLIT", "target_field")
PHASE1_MODEL = os.path.join(BASE_DIR, "MODEL", "phase1_base.keras")
PHASE1_MODEL_H5 = PHASE1_MODEL.replace(".keras", ".h5")
FINAL_KERAS = os.path.join(BASE_DIR, "MODEL", "tomoleafnet_v4_final.keras")
FINAL_H5 = FINAL_KERAS.replace(".keras", ".h5")
FINAL_TFLITE = os.path.join(BASE_DIR, "MODEL", "tomoleafnet_v4.tflite")
RESULTS_DIR = os.path.join(BASE_DIR, "RESULTS")
CURVES_PATH = os.path.join(RESULTS_DIR, "Phase2_Curves.png")
CSV_LOG_PATH = os.path.join(RESULTS_DIR, "Phase2_History.csv")

IMG_SIZE = 224
BATCH_SIZE = 32
SEED = 42

# 3-stage progressive unfreeze
STAGE1_EPOCHS = 20   # Last 30 layers
STAGE2_EPOCHS = 20   # Last 60 layers
STAGE3_EPOCHS = 45   # Full model
TOTAL_EPOCHS = STAGE1_EPOCHS + STAGE2_EPOCHS + STAGE3_EPOCHS  # 85

# Mixup alpha (reduced from 0.2 for less noise)
MIXUP_ALPHA = 0.1

# ── Augmentation (training only) ─────────────────────────────────────
# Keras Sequential augmentation block — spatial + photometric transforms.
# Vertical flip removed: tomato leaves have a natural orientation.
augment = tf.keras.Sequential([
    layers.RandomFlip("horizontal"),
    layers.RandomRotation(0.25),
    layers.RandomZoom((-0.3, 0.15)),
    layers.RandomTranslation(0.2, 0.2),
    layers.RandomContrast(0.3),
    layers.RandomBrightness(0.3),
    layers.GaussianNoise(0.06),  # ~15/255, simulate mobile sensor noise
])


# ── Extra augmentations for real-world robustness ────────────────────
# These cover conditions common in Philippine field capture that Keras
# built-in layers don't support: motion blur, shadows, and occlusion.

def random_motion_blur(images, max_kernel=7):
    """Simulate hand-shake / wind motion blur with a horizontal kernel."""
    def _blur(imgs):
        k = tf.random.uniform([], 3, max_kernel + 1, dtype=tf.int32)
        # Build a 1D horizontal averaging kernel
        kernel = tf.ones([1, k, 1, 1], dtype=tf.float32) / tf.cast(k, tf.float32)
        # Apply per-channel
        channels = tf.split(imgs, 3, axis=-1)
        blurred = tf.concat(
            [tf.nn.depthwise_conv2d(c, kernel, [1, 1, 1, 1], "SAME") for c in channels],
            axis=-1,
        )
        return blurred

    apply = tf.random.uniform([]) < 0.3  # 30% probability
    return tf.cond(apply, lambda: _blur(images), lambda: images)


def random_shadow(images):
    """Overlay a random dark rectangle to simulate partial shade / canopy shadow."""
    def _shadow(imgs):
        shape = tf.shape(imgs)
        batch, h, w = shape[0], shape[1], shape[2]
        # Random rectangle covering 20-50% of the image
        y1 = tf.random.uniform([], 0.0, 0.5)
        x1 = tf.random.uniform([], 0.0, 0.5)
        y2 = tf.random.uniform([], y1 + 0.2, tf.minimum(y1 + 0.5, 1.0))
        x2 = tf.random.uniform([], x1 + 0.2, tf.minimum(x1 + 0.5, 1.0))
        # Build mask: 1.0 outside shadow, 0.5-0.8 inside (darken)
        darken = tf.random.uniform([], 0.5, 0.8)
        rows = tf.cast(tf.range(h), tf.float32) / tf.cast(h, tf.float32)
        cols = tf.cast(tf.range(w), tf.float32) / tf.cast(w, tf.float32)
        row_mask = tf.cast((rows >= y1) & (rows < y2), tf.float32)
        col_mask = tf.cast((cols >= x1) & (cols < x2), tf.float32)
        mask = tf.einsum("h,w->hw", row_mask, col_mask)  # [H, W]
        mask = 1.0 - mask * (1.0 - darken)  # shadow region gets darkened
        mask = tf.reshape(mask, [1, h, w, 1])
        return imgs * mask

    apply = tf.random.uniform([]) < 0.3  # 30% probability
    return tf.cond(apply, lambda: _shadow(images), lambda: images)


def random_erasing(images, max_patches=3):
    """CoarseDropout / RandomErasing: black-out small rectangles to simulate
    occlusion by fingers, stakes, or overlapping leaves."""
    def _erase(imgs):
        shape = tf.shape(imgs)
        h, w = shape[1], shape[2]
        result = imgs
        num_patches = tf.random.uniform([], 1, max_patches + 1, dtype=tf.int32)
        for _ in range(max_patches):
            ph = tf.random.uniform([], 10, h // 5, dtype=tf.int32)
            pw = tf.random.uniform([], 10, w // 5, dtype=tf.int32)
            py = tf.random.uniform([], 0, h - ph, dtype=tf.int32)
            px = tf.random.uniform([], 0, w - pw, dtype=tf.int32)
            # Build a mask with 0 in the erased rectangle, 1 elsewhere
            mask = tf.ones_like(result)
            indices_h = tf.range(py, py + ph)
            indices_w = tf.range(px, px + pw)
            # Use padding to create the erased region
            pad_mask = tf.pad(
                tf.zeros([1, ph, pw, 3]),
                [[0, 0], [py, h - py - ph], [px, w - px - pw], [0, 0]],
                constant_values=1.0,
            )
            result = result * pad_mask
        return result

    apply = tf.random.uniform([]) < 0.25  # 25% probability
    return tf.cond(apply, lambda: _erase(images), lambda: images)


# ── Cosine decay with linear warmup ──────────────────────────────────

@tf.keras.utils.register_keras_serializable()
class WarmupCosineDecay(tf.keras.optimizers.schedules.LearningRateSchedule):
    """Linear warmup for `warmup_steps`, then cosine decay to `min_lr`."""

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

        # Linear warmup
        warmup_lr = self.base_lr * (step / tf.maximum(warmup_steps, 1.0))

        # Cosine decay
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


# ── Mixup augmentation ───────────────────────────────────────────────

def mixup(images, labels, alpha=MIXUP_ALPHA):
    """Apply Mixup: blend pairs of images/labels with a random ratio."""
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
    """Apply spatial augmentation, extra real-world augmentations, Mixup,
    then MobileNetV3 preprocessing."""
    images = augment(images, training=True)
    # Extra augmentations for field-capture robustness
    images = random_motion_blur(images)
    images = random_shadow(images)
    images = random_erasing(images)
    images = tf.clip_by_value(images, 0.0, 255.0)
    images, labels = mixup(images, labels)
    # Normalize [0, 255] -> [-1, 1] after augmentation
    images = tf.keras.applications.mobilenet_v3.preprocess_input(images)
    return images, labels


# ── Compute class weights ─────────────────────────────────────────────

def compute_class_weights(train_dir, class_names):
    """Compute class weights inversely proportional to sample count."""
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

    print("\n── Class Weights ──")
    for idx, cls in enumerate(class_names):
        print(f"  {cls}: {counts[idx]} samples -> weight {weights[idx]:.3f}")
    print()

    return weights


# ── Progressive unfreezing helpers ────────────────────────────────────

def get_base_model(model):
    """Find the MobileNetV3Large functional model inside the wrapper."""
    for layer in model.layers:
        if isinstance(layer, tf.keras.Model):
            return layer
    raise ValueError("Could not find base model (tf.keras.Model) in layers")


def unfreeze_last_n_layers(base, n):
    """Freeze all layers except the last n in the base model."""
    for layer in base.layers:
        layer.trainable = False
    for layer in base.layers[-n:]:
        layer.trainable = True

    trainable_count = sum(1 for l in base.layers if l.trainable)
    frozen_count = sum(1 for l in base.layers if not l.trainable)
    print(f"  Base model: {trainable_count} trainable, {frozen_count} frozen")


def compile_stage(model, base_lr, total_steps, warmup_epochs, steps_per_epoch):
    """Compile the model with cosine decay LR for a training stage."""
    warmup_steps = steps_per_epoch * warmup_epochs
    lr_schedule = WarmupCosineDecay(
        base_lr=base_lr,
        total_steps=total_steps,
        warmup_steps=warmup_steps,
        min_lr=1e-7,
    )
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=lr_schedule),
        loss=tf.keras.losses.CategoricalCrossentropy(),
        metrics=["accuracy"],
    )


# ── Main training function ────────────────────────────────────────────

def train():
    """Three-stage progressive fine-tuning on field data."""

    # ── Load datasets ─────────────────────────────────────────────────
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

    train_ds_aug = train_ds.map(
        augment_and_mixup,
        num_parallel_calls=tf.data.AUTOTUNE,
    )

    # Preprocess val images: [0, 255] -> [-1, 1]
    def preprocess_ds(images, labels):
        images = tf.keras.applications.mobilenet_v3.preprocess_input(images)
        return images, labels

    AUTOTUNE = tf.data.AUTOTUNE
    train_ds_aug = train_ds_aug.prefetch(AUTOTUNE)
    val_ds = val_ds.map(preprocess_ds, num_parallel_calls=AUTOTUNE).prefetch(AUTOTUNE)

    steps_per_epoch = len(train_ds)

    # ── Load Phase 1 model ────────────────────────────────────────────
    phase1_model_path = PHASE1_MODEL if os.path.exists(PHASE1_MODEL) else PHASE1_MODEL_H5
    if not os.path.exists(phase1_model_path):
        raise FileNotFoundError(
            "Could not find a Phase 1 model. Expected one of:\n"
            f"  - {PHASE1_MODEL}\n"
            f"  - {PHASE1_MODEL_H5}"
        )

    print(f"\nLoading Phase 1 model: {phase1_model_path}")
    model = tf.keras.models.load_model(phase1_model_path)
    base = get_base_model(model)
    print(f"Base model has {len(base.layers)} layers total")

    os.makedirs(os.path.dirname(FINAL_KERAS), exist_ok=True)
    os.makedirs(RESULTS_DIR, exist_ok=True)

    # Use .h5 for checkpoints to avoid Keras 3 save_model options bug,
    # then convert to .keras at the end before TFLite export.
    h5_checkpoint = FINAL_KERAS.replace(".keras", ".h5")

    # CSVLogger persists epoch metrics to disk — survives crashes
    csv_logger = tf.keras.callbacks.CSVLogger(CSV_LOG_PATH, append=False)

    all_histories = []

    # ==================================================================
    # STAGE 1: Unfreeze last 30 layers (20 epochs)
    # ==================================================================
    print("\n" + "=" * 60)
    print("  STAGE 1: Unfreeze last 30 layers")
    print("=" * 60)

    unfreeze_last_n_layers(base, 30)
    compile_stage(
        model,
        base_lr=5e-5,
        total_steps=steps_per_epoch * STAGE1_EPOCHS,
        warmup_epochs=2,
        steps_per_epoch=steps_per_epoch,
    )

    stage1_cbs = [
        tf.keras.callbacks.ModelCheckpoint(
            h5_checkpoint, monitor="val_accuracy", save_best_only=True, verbose=1,
        ),
        csv_logger,
    ]

    print(f"\nTraining Stage 1 for {STAGE1_EPOCHS} epochs...")
    h1 = model.fit(
        train_ds_aug,
        validation_data=val_ds,
        epochs=STAGE1_EPOCHS,
        callbacks=stage1_cbs,
        class_weight=class_weights,
    )
    all_histories.append(h1)

    # Switch CSVLogger to append mode for remaining stages
    csv_logger = tf.keras.callbacks.CSVLogger(CSV_LOG_PATH, append=True)

    # ==================================================================
    # STAGE 2: Unfreeze last 60 layers (20 epochs)
    # ==================================================================
    print("\n" + "=" * 60)
    print("  STAGE 2: Unfreeze last 60 layers")
    print("=" * 60)

    unfreeze_last_n_layers(base, 60)
    compile_stage(
        model,
        base_lr=3e-5,
        total_steps=steps_per_epoch * STAGE2_EPOCHS,
        warmup_epochs=2,
        steps_per_epoch=steps_per_epoch,
    )

    stage2_cbs = [
        tf.keras.callbacks.ModelCheckpoint(
            h5_checkpoint, monitor="val_accuracy", save_best_only=True, verbose=1,
        ),
        csv_logger,
    ]

    print(f"\nTraining Stage 2 for {STAGE2_EPOCHS} epochs...")
    h2 = model.fit(
        train_ds_aug,
        validation_data=val_ds,
        epochs=STAGE2_EPOCHS,
        callbacks=stage2_cbs,
        class_weight=class_weights,
    )
    all_histories.append(h2)

    # ==================================================================
    # STAGE 3: Unfreeze full model (45 epochs)
    # ==================================================================
    print("\n" + "=" * 60)
    print("  STAGE 3: Unfreeze full model")
    print("=" * 60)

    base.trainable = True
    trainable_count = sum(1 for l in base.layers if l.trainable)
    print(f"  Base model: all {trainable_count} layers now trainable")

    compile_stage(
        model,
        base_lr=1e-5,
        total_steps=steps_per_epoch * STAGE3_EPOCHS,
        warmup_epochs=2,
        steps_per_epoch=steps_per_epoch,
    )

    stage3_cbs = [
        tf.keras.callbacks.EarlyStopping(
            monitor="val_loss", patience=12, restore_best_weights=True, verbose=1,
        ),
        tf.keras.callbacks.ModelCheckpoint(
            h5_checkpoint, monitor="val_accuracy", save_best_only=True, verbose=1,
        ),
        csv_logger,
    ]

    print(f"\nTraining Stage 3 for up to {STAGE3_EPOCHS} epochs...")
    h3 = model.fit(
        train_ds_aug,
        validation_data=val_ds,
        epochs=STAGE3_EPOCHS,
        callbacks=stage3_cbs,
        class_weight=class_weights,
    )
    all_histories.append(h3)

    # ── Merge histories ───────────────────────────────────────────────
    full_history = {}
    for key in all_histories[0].history:
        full_history[key] = []
        for h in all_histories:
            full_history[key].extend(h.history[key])

    # ── Plot training curves ──────────────────────────────────────────
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))
    total_ran = len(full_history["accuracy"])

    s1_end = STAGE1_EPOCHS - 1
    s2_end = STAGE1_EPOCHS + STAGE2_EPOCHS - 1

    ax1.plot(full_history["accuracy"], label="Train Accuracy")
    ax1.plot(full_history["val_accuracy"], label="Val Accuracy")
    ax1.axvline(x=s1_end, color="gray", linestyle="--", alpha=0.5,
                label=f"Stage 1->2 (epoch {STAGE1_EPOCHS})")
    ax1.axvline(x=s2_end, color="red", linestyle="--", alpha=0.4,
                label=f"Stage 2->3 (epoch {STAGE1_EPOCHS + STAGE2_EPOCHS})")
    ax1.set_title("Phase 2 — Accuracy (3-Stage Progressive Unfreeze)")
    ax1.set_xlabel("Epoch")
    ax1.set_ylabel("Accuracy")
    ax1.legend(fontsize=8)
    ax1.grid(True, alpha=0.3)

    ax2.plot(full_history["loss"], label="Train Loss")
    ax2.plot(full_history["val_loss"], label="Val Loss")
    ax2.axvline(x=s1_end, color="gray", linestyle="--", alpha=0.5,
                label=f"Stage 1->2 (epoch {STAGE1_EPOCHS})")
    ax2.axvline(x=s2_end, color="red", linestyle="--", alpha=0.4,
                label=f"Stage 2->3 (epoch {STAGE1_EPOCHS + STAGE2_EPOCHS})")
    ax2.set_title("Phase 2 — Loss (3-Stage Progressive Unfreeze)")
    ax2.set_xlabel("Epoch")
    ax2.set_ylabel("Loss")
    ax2.legend(fontsize=8)
    ax2.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(CURVES_PATH, dpi=150)
    print(f"\nTraining curves saved to: {CURVES_PATH}")

    # ── Load best checkpoint and try native .keras export ───────────
    print(f"\nLoading best checkpoint: {h5_checkpoint}")
    best_model = tf.keras.models.load_model(
        h5_checkpoint,
        custom_objects={"WarmupCosineDecay": WarmupCosineDecay},
    )
    try:
        print(f"Converting {h5_checkpoint} -> {FINAL_KERAS}")
        best_model.save(FINAL_KERAS)
    except ValueError as e:
        if "not supported with the native Keras format" not in str(e):
            raise
        print(
            "Native .keras export is not supported in this environment. "
            f"Keeping the compatible H5 checkpoint instead: {FINAL_H5}"
        )

    # ── Export TFLite ─────────────────────────────────────────────────
    print("Exporting TFLite model...")

    # Save to SavedModel in system temp dir to avoid OneDrive file locks
    import shutil
    import tempfile
    saved_model_dir = os.path.join(tempfile.gettempdir(), "tomoleafnet_saved_model")
    if os.path.exists(saved_model_dir):
        shutil.rmtree(saved_model_dir)
    best_model.export(saved_model_dir)

    converter = tf.lite.TFLiteConverter.from_saved_model(saved_model_dir)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = converter.convert()

    with open(FINAL_TFLITE, "wb") as f:
        f.write(tflite_model)

    shutil.rmtree(saved_model_dir, ignore_errors=True)

    tflite_size_mb = os.path.getsize(FINAL_TFLITE) / (1024 * 1024)
    print(f"TFLite model saved to: {FINAL_TFLITE} ({tflite_size_mb:.2f} MB)")

    # ── Final metrics ─────────────────────────────────────────────────
    all_val_acc = full_history["val_accuracy"]
    best_epoch = all_val_acc.index(max(all_val_acc))
    print(f"\nTotal epochs trained: {total_ran}")
    print(f"Best epoch: {best_epoch + 1}")
    print(f"Best val accuracy: {max(all_val_acc):.4f}")
    print(f"Final train accuracy: {full_history['accuracy'][-1]:.4f}")
    print(f"Final val accuracy:  {full_history['val_accuracy'][-1]:.4f}")


if __name__ == "__main__":
    train()
