"""
train_detector.py — Train the real-time tomato-leaf detector.

Builds a lightweight MobileNetV2 binary classifier on detector_dataset/,
fine-tunes it, and exports a float16-quantized TFLite model for Flutter.

Usage:
    python train_detector.py
"""

import os
import shutil
import tempfile

import tensorflow as tf
from tensorflow.keras import callbacks, layers, models, optimizers

tf.keras.backend.clear_session()

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(BASE_DIR, "detector_dataset")
MODEL_DIR = os.path.join(BASE_DIR, "DETECTOR_MODEL")
KERAS_PATH = os.path.join(MODEL_DIR, "detector_final.keras")
TFLITE_PATH = os.path.join(MODEL_DIR, "tomoleafnet_detector.tflite")

CLASS_NAMES = ["not_tomato_leaf", "tomato_leaf"]
IMG_SIZE = (224, 224)
BATCH_SIZE = 32
HEAD_EPOCHS = 10
FINE_TUNE_EPOCHS = 20
SEED = 42


def preprocess_dataset(images, labels):
    images = tf.keras.applications.mobilenet_v2.preprocess_input(images)
    return images, labels


def build_model():
    base = tf.keras.applications.MobileNetV2(
        input_shape=(224, 224, 3),
        include_top=False,
        weights="imagenet",
    )
    base.trainable = False

    inputs = layers.Input(shape=(224, 224, 3))
    x = base(inputs, training=False)
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.Dropout(0.3)(x)
    outputs = layers.Dense(2, activation="softmax")(x)

    model = models.Model(inputs, outputs)
    return model, base


def export_tflite():
    print("\nExporting float16 TFLite detector...")
    best_model = tf.keras.models.load_model(KERAS_PATH, compile=False)
    saved_model_dir = os.path.join(
        tempfile.gettempdir(),
        "tomoleafnet_detector_saved_model",
    )

    if os.path.exists(saved_model_dir):
        shutil.rmtree(saved_model_dir)

    best_model.export(saved_model_dir)

    converter = tf.lite.TFLiteConverter.from_saved_model(saved_model_dir)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    tflite_model = converter.convert()

    with open(TFLITE_PATH, "wb") as handle:
        handle.write(tflite_model)

    shutil.rmtree(saved_model_dir, ignore_errors=True)

    size_mb = os.path.getsize(TFLITE_PATH) / (1024 * 1024)
    print(f"Detector TFLite saved: {TFLITE_PATH} ({size_mb:.2f} MB)")


def main():
    os.makedirs(MODEL_DIR, exist_ok=True)

    train_ds = tf.keras.utils.image_dataset_from_directory(
        os.path.join(DATA_DIR, "train"),
        image_size=IMG_SIZE,
        batch_size=BATCH_SIZE,
        label_mode="categorical",
        shuffle=True,
        seed=SEED,
    )
    val_ds = tf.keras.utils.image_dataset_from_directory(
        os.path.join(DATA_DIR, "val"),
        image_size=IMG_SIZE,
        batch_size=BATCH_SIZE,
        label_mode="categorical",
        shuffle=False,
    )

    print(f"Class names: {train_ds.class_names}")
    assert train_ds.class_names == CLASS_NAMES, (
        f"Expected class order {CLASS_NAMES}, got {train_ds.class_names}"
    )
    assert val_ds.class_names == CLASS_NAMES, (
        f"Expected class order {CLASS_NAMES}, got {val_ds.class_names}"
    )

    autotune = tf.data.AUTOTUNE
    train_ds = train_ds.map(preprocess_dataset, num_parallel_calls=autotune).prefetch(autotune)
    val_ds = val_ds.map(preprocess_dataset, num_parallel_calls=autotune).prefetch(autotune)

    model, base = build_model()

    print("\nPhase 1: train classification head")
    model.compile(
        optimizer=optimizers.Adam(1e-3),
        loss="categorical_crossentropy",
        metrics=["accuracy"],
    )
    model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=HEAD_EPOCHS,
        verbose=1,
    )

    print("\nPhase 2: fine-tune full MobileNetV2")
    base.trainable = True
    model.compile(
        optimizer=optimizers.Adam(1e-5),
        loss="categorical_crossentropy",
        metrics=["accuracy"],
    )

    training_callbacks = [
        callbacks.EarlyStopping(
            monitor="val_accuracy",
            patience=5,
            restore_best_weights=True,
            verbose=1,
        ),
        callbacks.ModelCheckpoint(
            KERAS_PATH,
            monitor="val_accuracy",
            save_best_only=True,
            verbose=1,
        ),
        callbacks.ReduceLROnPlateau(
            monitor="val_accuracy",
            factor=0.5,
            patience=3,
            min_lr=1e-7,
            verbose=1,
        ),
    ]

    history = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=FINE_TUNE_EPOCHS,
        callbacks=training_callbacks,
        verbose=1,
    )

    best_val = max(history.history["val_accuracy"])
    final_val = history.history["val_accuracy"][-1]
    print(f"\nBest val accuracy:  {best_val:.4f}")
    print(f"Final val accuracy: {final_val:.4f}")

    export_tflite()


if __name__ == "__main__":
    main()
