"""
2_train_phase2_v2.py - Phase 2 fine-tuning on the field dataset (MobileNetV2).

This keeps the same Phase 2 method as the current v5 MobileNetV3Large pipeline:
  - proper Mixup with Beta(alpha, alpha)
  - horizontal-only flip
  - label smoothing 0.1
  - frozen BatchNorm during all unfreeze stages
  - moderate augmentation
  - 3-stage progressive unfreeze
  - cosine LR with warmup

The only intended change is the backbone: MobileNetV2 instead of
MobileNetV3Large.

Prerequisites:
    - Run 0_augment_field_dataset.py first
    - Run 1_train_phase1_v2.py first

Outputs:
    - MODEL/tomoleafnet_v2_final.keras
    - MODEL/tomoleafnet_v2_final.h5
    - MODEL/tomoleafnet_v2.tflite
    - RESULTS/Phase2_Curves_v2.png
    - RESULTS/Phase2_History_v2.csv

Usage:
    python 2_train_phase2_v2.py
"""

import math
import os

import matplotlib.pyplot as plt
import tensorflow as tf
from tensorflow.keras import layers

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
FIELD_DATA_DIR = os.path.join(BASE_DIR, "DATA-SPLIT", "target_field")
PHASE1_MODEL = os.path.join(BASE_DIR, "MODEL", "phase1_base_v2.keras")
PHASE1_MODEL_H5 = PHASE1_MODEL.replace(".keras", ".h5")
FINAL_KERAS = os.path.join(BASE_DIR, "MODEL", "tomoleafnet_v2_final.keras")
FINAL_H5 = FINAL_KERAS.replace(".keras", ".h5")
FINAL_TFLITE = os.path.join(BASE_DIR, "MODEL", "tomoleafnet_v2.tflite")
RESULTS_DIR = os.path.join(BASE_DIR, "RESULTS")
CURVES_PATH = os.path.join(RESULTS_DIR, "Phase2_Curves_v2.png")
CSV_LOG_PATH = os.path.join(RESULTS_DIR, "Phase2_History_v2.csv")

IMG_SIZE = 224
BATCH_SIZE = 32
SEED = 42

STAGE1_EPOCHS = 20
STAGE2_EPOCHS = 20
STAGE3_EPOCHS = 45
TOTAL_EPOCHS = STAGE1_EPOCHS + STAGE2_EPOCHS + STAGE3_EPOCHS

MIXUP_ALPHA = 0.2

augment = tf.keras.Sequential([
    layers.RandomFlip("horizontal"),
    layers.RandomRotation(0.15),
    layers.RandomZoom((-0.2, 0.10)),
    layers.RandomTranslation(0.15, 0.15),
    layers.RandomContrast(0.2),
    layers.RandomBrightness(0.2),
])


def random_motion_blur(images, max_kernel=7):
    """Simulate hand-shake / wind motion blur with a horizontal kernel."""

    def _blur(imgs):
        k = tf.random.uniform([], 3, max_kernel + 1, dtype=tf.int32)
        kernel = tf.ones([1, k, 1, 1], dtype=tf.float32) / tf.cast(k, tf.float32)
        channels = tf.split(imgs, 3, axis=-1)
        blurred = tf.concat(
            [tf.nn.depthwise_conv2d(c, kernel, [1, 1, 1, 1], "SAME") for c in channels],
            axis=-1,
        )
        return blurred

    apply = tf.random.uniform([]) < 0.15
    return tf.cond(apply, lambda: _blur(images), lambda: images)


def random_shadow(images):
    """Overlay a random dark rectangle to simulate partial shade."""

    def _shadow(imgs):
        shape = tf.shape(imgs)
        h, w = shape[1], shape[2]
        y1 = tf.random.uniform([], 0.0, 0.5)
        x1 = tf.random.uniform([], 0.0, 0.5)
        y2 = tf.random.uniform([], y1 + 0.2, tf.minimum(y1 + 0.5, 1.0))
        x2 = tf.random.uniform([], x1 + 0.2, tf.minimum(x1 + 0.5, 1.0))
        darken = tf.random.uniform([], 0.5, 0.8)
        rows = tf.cast(tf.range(h), tf.float32) / tf.cast(h, tf.float32)
        cols = tf.cast(tf.range(w), tf.float32) / tf.cast(w, tf.float32)
        row_mask = tf.cast((rows >= y1) & (rows < y2), tf.float32)
        col_mask = tf.cast((cols >= x1) & (cols < x2), tf.float32)
        mask = tf.einsum("h,w->hw", row_mask, col_mask)
        mask = 1.0 - mask * (1.0 - darken)
        mask = tf.reshape(mask, [1, h, w, 1])
        return imgs * mask

    apply = tf.random.uniform([]) < 0.15
    return tf.cond(apply, lambda: _shadow(images), lambda: images)


@tf.keras.utils.register_keras_serializable()
class WarmupCosineDecay(tf.keras.optimizers.schedules.LearningRateSchedule):
    """Linear warmup for warmup_steps, then cosine decay to min_lr."""

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


def mixup(images, labels, alpha=MIXUP_ALPHA):
    """Apply Mixup with proper Beta(alpha, alpha) sampling via two Gamma draws."""
    batch_size = tf.shape(images)[0]

    g1 = tf.random.gamma(shape=[batch_size, 1, 1, 1], alpha=alpha)
    g2 = tf.random.gamma(shape=[batch_size, 1, 1, 1], alpha=alpha)
    lam = g1 / (g1 + g2 + 1e-7)
    lam = tf.maximum(lam, 1.0 - lam)
    lam = tf.clip_by_value(lam, 0.0, 1.0)

    lam_labels = tf.reshape(lam, [batch_size, 1])

    indices = tf.random.shuffle(tf.range(batch_size))
    shuffled_images = tf.gather(images, indices)
    shuffled_labels = tf.gather(labels, indices)

    mixed_images = lam * images + (1.0 - lam) * shuffled_images
    mixed_labels = lam_labels * labels + (1.0 - lam_labels) * shuffled_labels

    return mixed_images, mixed_labels


def augment_and_mixup(images, labels):
    """Apply augmentation, extra field augments, Mixup, then normalize."""
    images = augment(images, training=True)
    images = random_motion_blur(images)
    images = random_shadow(images)
    images = tf.clip_by_value(images, 0.0, 255.0)
    images, labels = mixup(images, labels)
    images = tf.keras.applications.mobilenet_v2.preprocess_input(images)
    return images, labels


def compute_class_weights(train_dir, class_names):
    """Compute class weights inversely proportional to sample count."""
    counts = {}
    for i, cls in enumerate(class_names):
        cls_dir = os.path.join(train_dir, cls)
        counts[i] = len([f for f in os.listdir(cls_dir) if not f.startswith(".")])

    total = sum(counts.values())
    n_classes = len(counts)
    weights = {}
    for idx, count in counts.items():
        weights[idx] = total / (n_classes * count)

    print("\n--- Class Weights ---")
    for idx, cls in enumerate(class_names):
        print(f"  {cls}: {counts[idx]} samples -> weight {weights[idx]:.3f}")
    print()

    return weights


def get_base_model(model):
    """Find the backbone model inside the wrapper model."""
    for layer in model.layers:
        if isinstance(layer, tf.keras.Model):
            return layer
    raise ValueError("Could not find base model (tf.keras.Model) in layers")


def unfreeze_last_n_layers(base, n):
    """Freeze all layers except the last n, excluding BatchNorm."""
    for layer in base.layers:
        layer.trainable = False
    for layer in base.layers[-n:]:
        if not isinstance(layer, tf.keras.layers.BatchNormalization):
            layer.trainable = True

    trainable_count = sum(1 for layer in base.layers if layer.trainable)
    frozen_count = sum(1 for layer in base.layers if not layer.trainable)
    print(f"  Base model: {trainable_count} trainable, {frozen_count} frozen (BN frozen)")


def unfreeze_full_backbone(base):
    """Unfreeze all layers except BatchNorm."""
    for layer in base.layers:
        layer.trainable = not isinstance(layer, tf.keras.layers.BatchNormalization)

    trainable_count = sum(1 for layer in base.layers if layer.trainable)
    frozen_count = sum(1 for layer in base.layers if not layer.trainable)
    print(f"  Base model: {trainable_count} trainable, {frozen_count} frozen (BN frozen)")


def compile_stage(model, base_lr, total_steps, warmup_epochs, steps_per_epoch):
    """Compile with cosine decay LR plus label smoothing."""
    warmup_steps = steps_per_epoch * warmup_epochs
    lr_schedule = WarmupCosineDecay(
        base_lr=base_lr,
        total_steps=total_steps,
        warmup_steps=warmup_steps,
        min_lr=1e-7,
    )
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=lr_schedule),
        loss=tf.keras.losses.CategoricalCrossentropy(label_smoothing=0.1),
        metrics=["accuracy"],
    )


def train():
    """Three-stage progressive fine-tuning on field data."""
    train_ds = tf.keras.utils.image_dataset_from_directory(
        os.path.join(FIELD_DATA_DIR, "train"),
        image_size=(IMG_SIZE, IMG_SIZE),
        crop_to_aspect_ratio=True,
        batch_size=BATCH_SIZE,
        label_mode="categorical",
        seed=SEED,
        shuffle=True,
    )

    val_ds = tf.keras.utils.image_dataset_from_directory(
        os.path.join(FIELD_DATA_DIR, "val"),
        image_size=(IMG_SIZE, IMG_SIZE),
        crop_to_aspect_ratio=True,
        batch_size=BATCH_SIZE,
        label_mode="categorical",
        seed=SEED,
        shuffle=False,
    )

    class_names = train_ds.class_names
    print(f"Class names: {class_names}")

    class_weights = compute_class_weights(
        os.path.join(FIELD_DATA_DIR, "train"),
        class_names,
    )

    train_ds_aug = train_ds.map(
        augment_and_mixup,
        num_parallel_calls=tf.data.AUTOTUNE,
    )

    def preprocess_ds(images, labels):
        images = tf.keras.applications.mobilenet_v2.preprocess_input(images)
        return images, labels

    autotune = tf.data.AUTOTUNE
    train_ds_aug = train_ds_aug.prefetch(autotune)
    val_ds = val_ds.map(preprocess_ds, num_parallel_calls=autotune).prefetch(autotune)

    steps_per_epoch = len(train_ds)

    phase1_model_path = PHASE1_MODEL if os.path.exists(PHASE1_MODEL) else PHASE1_MODEL_H5
    if not os.path.exists(phase1_model_path):
        raise FileNotFoundError(
            "Could not find a Phase 1 MobileNetV2 model. Expected one of:\n"
            f"  - {PHASE1_MODEL}\n"
            f"  - {PHASE1_MODEL_H5}"
        )

    print(f"\nLoading Phase 1 model: {phase1_model_path}")
    model = tf.keras.models.load_model(phase1_model_path)
    base = get_base_model(model)
    print(f"Base model has {len(base.layers)} layers total")

    os.makedirs(os.path.dirname(FINAL_KERAS), exist_ok=True)
    os.makedirs(RESULTS_DIR, exist_ok=True)

    h5_checkpoint = FINAL_H5
    csv_logger = tf.keras.callbacks.CSVLogger(CSV_LOG_PATH, append=False)
    all_histories = []

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
            h5_checkpoint,
            monitor="val_accuracy",
            save_best_only=True,
            verbose=1,
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

    csv_logger = tf.keras.callbacks.CSVLogger(CSV_LOG_PATH, append=True)

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
            h5_checkpoint,
            monitor="val_accuracy",
            save_best_only=True,
            verbose=1,
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

    print("\n" + "=" * 60)
    print("  STAGE 3: Unfreeze full model")
    print("=" * 60)
    unfreeze_full_backbone(base)
    compile_stage(
        model,
        base_lr=1e-5,
        total_steps=steps_per_epoch * STAGE3_EPOCHS,
        warmup_epochs=2,
        steps_per_epoch=steps_per_epoch,
    )

    stage3_cbs = [
        tf.keras.callbacks.EarlyStopping(
            monitor="val_loss",
            patience=12,
            restore_best_weights=True,
            verbose=1,
        ),
        tf.keras.callbacks.ModelCheckpoint(
            h5_checkpoint,
            monitor="val_accuracy",
            save_best_only=True,
            verbose=1,
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

    full_history = {}
    for key in all_histories[0].history:
        full_history[key] = []
        for history in all_histories:
            full_history[key].extend(history.history[key])

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))
    total_ran = len(full_history["accuracy"])
    s1_end = STAGE1_EPOCHS - 1
    s2_end = STAGE1_EPOCHS + STAGE2_EPOCHS - 1

    ax1.plot(full_history["accuracy"], label="Train Accuracy")
    ax1.plot(full_history["val_accuracy"], label="Val Accuracy")
    ax1.axvline(
        x=s1_end,
        color="gray",
        linestyle="--",
        alpha=0.5,
        label=f"Stage 1->2 (epoch {STAGE1_EPOCHS})",
    )
    ax1.axvline(
        x=s2_end,
        color="red",
        linestyle="--",
        alpha=0.4,
        label=f"Stage 2->3 (epoch {STAGE1_EPOCHS + STAGE2_EPOCHS})",
    )
    ax1.set_title("Phase 2 v2 - Accuracy (3-stage progressive unfreeze)")
    ax1.set_xlabel("Epoch")
    ax1.set_ylabel("Accuracy")
    ax1.legend(fontsize=8)
    ax1.grid(True, alpha=0.3)

    ax2.plot(full_history["loss"], label="Train Loss")
    ax2.plot(full_history["val_loss"], label="Val Loss")
    ax2.axvline(
        x=s1_end,
        color="gray",
        linestyle="--",
        alpha=0.5,
        label=f"Stage 1->2 (epoch {STAGE1_EPOCHS})",
    )
    ax2.axvline(
        x=s2_end,
        color="red",
        linestyle="--",
        alpha=0.4,
        label=f"Stage 2->3 (epoch {STAGE1_EPOCHS + STAGE2_EPOCHS})",
    )
    ax2.set_title("Phase 2 v2 - Loss (3-stage progressive unfreeze)")
    ax2.set_xlabel("Epoch")
    ax2.set_ylabel("Loss")
    ax2.legend(fontsize=8)
    ax2.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(CURVES_PATH, dpi=150)
    print(f"\nTraining curves saved to: {CURVES_PATH}")

    print(f"\nLoading best checkpoint: {h5_checkpoint}")
    best_model = tf.keras.models.load_model(h5_checkpoint, compile=False)
    try:
        print(f"Converting {h5_checkpoint} -> {FINAL_KERAS}")
        best_model.save(FINAL_KERAS)
    except ValueError as exc:
        if "not supported with the native Keras format" not in str(exc):
            raise
        print(
            "Native .keras export is not supported in this environment. "
            f"Keeping the compatible H5 checkpoint instead: {FINAL_H5}"
        )

    print("Exporting TFLite model...")
    import shutil
    import tempfile

    saved_model_dir = os.path.join(tempfile.gettempdir(), "tomoleafnet_v2_saved_model")
    if os.path.exists(saved_model_dir):
        shutil.rmtree(saved_model_dir)
    best_model.export(saved_model_dir)

    converter = tf.lite.TFLiteConverter.from_saved_model(saved_model_dir)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = converter.convert()

    with open(FINAL_TFLITE, "wb") as file_obj:
        file_obj.write(tflite_model)

    shutil.rmtree(saved_model_dir, ignore_errors=True)

    tflite_size_mb = os.path.getsize(FINAL_TFLITE) / (1024 * 1024)
    print(f"TFLite model saved to: {FINAL_TFLITE} ({tflite_size_mb:.2f} MB)")

    all_val_acc = full_history["val_accuracy"]
    best_epoch = all_val_acc.index(max(all_val_acc))
    print(f"\nTotal epochs trained: {total_ran}")
    print(f"Best epoch: {best_epoch + 1}")
    print(f"Best val accuracy: {max(all_val_acc):.4f}")
    print(f"Final train accuracy: {full_history['accuracy'][-1]:.4f}")
    print(f"Final val accuracy:  {full_history['val_accuracy'][-1]:.4f}")


if __name__ == "__main__":
    train()
