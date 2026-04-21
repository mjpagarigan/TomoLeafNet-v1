"""
resume_stage3.py - Resume Stage 3 training from the best checkpoint.

Loads the best TomoLeafNet checkpoint, rebuilds the classifier graph so the
backbone is not trapped behind a baked `training=False` call, and continues
full-backbone fine-tuning with the same Stage 3 settings.

Usage:
    python resume_stage3.py
    python resume_stage3.py --export
"""

import math
import os
import sys

import tensorflow as tf
from tensorflow.keras import layers

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
FIELD_DATA_DIR = os.path.join(BASE_DIR, "DATA-SPLIT", "target_field")
FINAL_KERAS = os.path.join(BASE_DIR, "MODEL", "tomoleafnet_v5_final.keras")
FINAL_H5 = FINAL_KERAS.replace(".keras", ".h5")
FINAL_TFLITE = os.path.join(BASE_DIR, "MODEL", "tomoleafnet_v5.tflite")
RESULTS_DIR = os.path.join(BASE_DIR, "RESULTS")
CSV_LOG_PATH = os.path.join(RESULTS_DIR, "Resume_History_v5.csv")

IMG_SIZE = 224
BATCH_SIZE = 32
SEED = 42
RESUME_EPOCHS = 30


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


augment = tf.keras.Sequential([
    layers.RandomFlip("horizontal"),
    layers.RandomRotation(0.10),
    layers.RandomZoom((-0.15, 0.10)),
    layers.RandomTranslation(0.10, 0.10),
    layers.RandomContrast(0.15),
    layers.RandomBrightness(0.15),
    layers.GaussianNoise(15.0),
])


def resolve_model_path():
    return FINAL_KERAS if os.path.exists(FINAL_KERAS) else FINAL_H5


def random_motion_blur(images, max_kernel=7):
    """Simulate moderate hand-shake / wind blur."""
    def _blur(imgs):
        k = tf.random.uniform([], 3, max_kernel + 1, dtype=tf.int32)
        kernel = tf.ones([1, k, 1, 1], dtype=tf.float32) / tf.cast(k, tf.float32)
        channels = tf.split(imgs, 3, axis=-1)
        blurred = tf.concat(
            [tf.nn.depthwise_conv2d(c, kernel, [1, 1, 1, 1], "SAME") for c in channels],
            axis=-1,
        )
        return blurred

    return tf.cond(tf.random.uniform([]) < 0.15, lambda: _blur(images), lambda: images)


def random_shadow(images):
    """Overlay a dark rectangle to mimic partial canopy shadow."""
    def _shadow(imgs):
        shape = tf.shape(imgs)
        h = shape[1]
        w = shape[2]
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

    return tf.cond(tf.random.uniform([]) < 0.15, lambda: _shadow(images), lambda: images)


def random_erasing(images, max_patches=3):
    """Erase a few small rectangles to mimic leaf occlusion."""
    def _erase(imgs):
        shape = tf.shape(imgs)
        h = shape[1]
        w = shape[2]
        result = imgs
        num_patches = tf.random.uniform([], 1, max_patches + 1, dtype=tf.int32)
        for patch_idx in range(max_patches):
            current = result

            def apply_patch():
                ph = tf.random.uniform([], 10, h // 5, dtype=tf.int32)
                pw = tf.random.uniform([], 10, w // 5, dtype=tf.int32)
                py = tf.random.uniform([], 0, h - ph, dtype=tf.int32)
                px = tf.random.uniform([], 0, w - pw, dtype=tf.int32)
                pad_mask = tf.pad(
                    tf.zeros([1, ph, pw, 3]),
                    [[0, 0], [py, h - py - ph], [px, w - px - pw], [0, 0]],
                    constant_values=1.0,
                )
                return current * pad_mask

            result = tf.cond(
                tf.constant(patch_idx, dtype=tf.int32) < num_patches,
                apply_patch,
                lambda current=current: current,
            )
        return result

    return tf.cond(tf.random.uniform([]) < 0.15, lambda: _erase(images), lambda: images)


def augment_and_preprocess(images, labels):
    images = augment(images, training=True)
    images = random_motion_blur(images)
    images = random_shadow(images)
    images = random_erasing(images)
    images = tf.clip_by_value(images, 0.0, 255.0)
    images = tf.keras.applications.mobilenet_v3.preprocess_input(images)
    return images, labels


def preprocess_ds(images, labels):
    images = tf.keras.applications.mobilenet_v3.preprocess_input(images)
    return images, labels


def compute_class_weights(train_dir, class_names):
    """Compute class weights from real training files when available."""
    counts = {}
    class_files = {}

    for i, cls in enumerate(class_names):
        cls_dir = os.path.join(train_dir, cls)
        files = [f for f in os.listdir(cls_dir) if not f.startswith(".")]
        class_files[i] = files

    use_real_only = all(
        any("_train_real_" in file_name for file_name in files)
        for files in class_files.values()
    )

    for idx in range(len(class_names)):
        files = class_files[idx]
        if use_real_only:
            count = sum("_train_real_" in file_name for file_name in files)
        else:
            count = len(files)
        counts[idx] = max(count, 1)

    total = sum(counts.values())
    weights = {
        idx: total / (len(class_names) * count)
        for idx, count in counts.items()
    }

    source = "real-only train files" if use_real_only else "all train files"
    print(f"\nClass weights source: {source}")
    for idx, cls in enumerate(class_names):
        print(f"  {cls}: {counts[idx]} samples -> weight {weights[idx]:.3f}")
    print()
    return weights


def build_classifier_model(base_weights="imagenet"):
    """Build the MobileNetV3Large classifier without baking training=False."""
    base = tf.keras.applications.MobileNetV3Large(
        input_shape=(IMG_SIZE, IMG_SIZE, 3),
        include_top=False,
        weights=base_weights,
    )
    base.trainable = False

    inputs = tf.keras.Input(shape=(IMG_SIZE, IMG_SIZE, 3))
    x = base(inputs)
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.Dropout(0.3)(x)
    outputs = layers.Dense(5, activation="softmax")(x)
    model = tf.keras.Model(inputs, outputs)
    return model, base


def load_model_for_resume(model_path):
    """Rebuild the classifier graph so resumed fine-tuning can update it."""
    errors = []

    try:
        saved_model = tf.keras.models.load_model(model_path, compile=False)
        model, base = build_classifier_model(base_weights=None)
        model.set_weights(saved_model.get_weights())
        print(f"Loaded checkpoint via full-model deserialization: {model_path}")
        return model, base
    except Exception as exc:
        errors.append(f"{model_path} (full model): {type(exc).__name__}")

    h5_path = FINAL_H5 if os.path.exists(FINAL_H5) else model_path
    if h5_path.endswith(".h5") and os.path.exists(h5_path):
        try:
            model, base = build_classifier_model(base_weights=None)
            model.load_weights(h5_path, by_name=True, skip_mismatch=False)
            print(f"Loaded checkpoint via H5 weight fallback: {h5_path}")
            return model, base
        except Exception as exc:
            errors.append(f"{h5_path} (weights fallback): {type(exc).__name__}")

    joined = "\n".join(f"  - {err}" for err in errors)
    raise RuntimeError(f"Could not load a compatible resume checkpoint.\n{joined}")


def export_tflite():
    """Export the best checkpoint to TFLite."""
    model_path = resolve_model_path()
    print(f"\nLoading best checkpoint: {model_path}")
    model, _ = load_model_for_resume(model_path)

    print("Converting to TFLite...")
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

    print(f"Class names: {train_ds.class_names}")

    autotune = tf.data.AUTOTUNE
    train_ds_aug = train_ds.map(
        augment_and_preprocess,
        num_parallel_calls=autotune,
    ).prefetch(autotune)
    val_ds = val_ds.map(preprocess_ds, num_parallel_calls=autotune).prefetch(autotune)
    class_weights = compute_class_weights(os.path.join(FIELD_DATA_DIR, "train"), train_ds.class_names)

    steps_per_epoch = len(train_ds)

    model_path = resolve_model_path()
    print(f"\nLoading checkpoint: {model_path}")
    model, base = load_model_for_resume(model_path)

    for layer in base.layers:
        layer.trainable = not isinstance(layer, tf.keras.layers.BatchNormalization)

    print("\nValidating checkpoint accuracy...")
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=1e-5),
        loss=tf.keras.losses.CategoricalCrossentropy(),
        metrics=["accuracy"],
    )
    _, val_acc = model.evaluate(val_ds, verbose=1)
    print(f"Checkpoint val accuracy: {val_acc:.4f}")

    total_steps = steps_per_epoch * RESUME_EPOCHS
    warmup_steps = steps_per_epoch * 2

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

    os.makedirs(RESULTS_DIR, exist_ok=True)
    checkpoint_path = FINAL_H5
    callbacks = [
        tf.keras.callbacks.EarlyStopping(
            monitor="val_loss", patience=12, restore_best_weights=True, verbose=1,
        ),
        tf.keras.callbacks.ModelCheckpoint(
            checkpoint_path,
            monitor="val_accuracy",
            save_best_only=True,
            save_weights_only=False,
            verbose=1,
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

    best_model = tf.keras.models.load_model(checkpoint_path, compile=False)
    try:
        best_model.save(FINAL_KERAS)
    except ValueError as exc:
        if "not supported with the native Keras format" not in str(exc):
            raise
        print(
            "Native .keras export is not supported in this environment. "
            f"Keeping the compatible H5 checkpoint instead: {FINAL_H5}"
        )

    best_val_acc = max(history.history["val_accuracy"])
    print(f"\nBest val accuracy this run: {best_val_acc:.4f}")
    print(f"Final val accuracy:        {history.history['val_accuracy'][-1]:.4f}")

    export_tflite()


if __name__ == "__main__":
    if "--export" in sys.argv:
        export_tflite()
    else:
        resume_training()
