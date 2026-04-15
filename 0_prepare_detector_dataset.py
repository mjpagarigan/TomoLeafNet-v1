"""
0_prepare_detector_dataset.py — Build binary tomato-leaf detector dataset.

Creates a dedicated 2-class dataset for live camera gating:
  - tomato_leaf
  - not_tomato_leaf

Sources:
  - tomato_leaf: all images from DATA-SPLIT/target_field/train/
    Early_Blight, Healthy, Leaf_Miner, Leaf_Mold
  - not_tomato_leaf: images from DATA-SPLIT/target_field/train/Not_Tomato

If a class has fewer than TARGET_PER_CLASS real images, synthetic images are
generated and placed in the training split only. Validation and test remain
real-only to better reflect deployment performance.

Usage:
    python 0_prepare_detector_dataset.py
"""

import os
import random
import shutil

import tensorflow as tf
from tensorflow.keras import layers

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SOURCE_DIR = os.path.join(BASE_DIR, "DATA-SPLIT", "target_field", "train")
OUTPUT_DIR = os.path.join(BASE_DIR, "detector_dataset")

TOMATO_SOURCE_CLASSES = [
    "Early_Blight",
    "Healthy",
    "Leaf_Miner",
    "Leaf_Mold",
]
NOT_TOMATO_SOURCE_CLASS = "Not_Tomato"
TARGET_PER_CLASS = 1000
TRAIN_COUNT = 800
VAL_COUNT = 100
TEST_COUNT = 100
IMG_SIZE = 224
SEED = 42

VALID_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp"}

augment = tf.keras.Sequential([
    layers.RandomFlip("horizontal_and_vertical"),
    layers.RandomRotation(0.2),
    layers.RandomBrightness(0.3),
    layers.RandomContrast(0.2),
    layers.RandomZoom((-0.2, 0.1)),
])


def list_images(folder):
    files = []
    for name in os.listdir(folder):
        path = os.path.join(folder, name)
        if not os.path.isfile(path):
            continue
        if os.path.splitext(name)[1].lower() in VALID_EXTENSIONS:
            files.append(path)
    files.sort()
    return files


def load_and_resize(path):
    raw = tf.io.read_file(path)
    image = tf.image.decode_image(raw, channels=3, expand_animations=False)
    image = tf.image.resize(image, [IMG_SIZE, IMG_SIZE])
    return image


def save_image(tensor, path):
    image = tf.cast(tf.clip_by_value(tensor, 0, 255), tf.uint8)
    encoded = tf.io.encode_jpeg(image, quality=95)
    tf.io.write_file(path, encoded)


def gather_tomato_paths():
    paths = []
    for class_name in TOMATO_SOURCE_CLASSES:
        class_dir = os.path.join(SOURCE_DIR, class_name)
        if not os.path.isdir(class_dir):
            raise FileNotFoundError(f"Missing source folder: {class_dir}")
        paths.extend(list_images(class_dir))
    return sorted(paths)


def gather_not_tomato_paths():
    class_dir = os.path.join(SOURCE_DIR, NOT_TOMATO_SOURCE_CLASS)
    if not os.path.isdir(class_dir):
        raise FileNotFoundError(f"Missing source folder: {class_dir}")
    return list_images(class_dir)


def build_class_pool(label, real_paths):
    rng = random.Random(SEED + hash(label))
    shuffled_paths = list(real_paths)
    rng.shuffle(shuffled_paths)

    selected_real = shuffled_paths[: min(len(shuffled_paths), TARGET_PER_CLASS)]
    synthetic_needed = TARGET_PER_CLASS - len(selected_real)
    synthetic_tensors = []

    if len(selected_real) < VAL_COUNT + TEST_COUNT:
        raise ValueError(
            f"{label} needs at least {VAL_COUNT + TEST_COUNT} real images "
            f"to keep val/test real-only, but found {len(selected_real)}."
        )

    if synthetic_needed > 0:
        print(f"  {label}: {len(selected_real)} real + {synthetic_needed} synthetic")
        source_images = [load_and_resize(path) for path in selected_real]
        for _ in range(synthetic_needed):
            source_index = rng.randint(0, len(source_images) - 1)
            aug_image = augment(
                tf.expand_dims(source_images[source_index], axis=0),
                training=True,
            )[0]
            synthetic_tensors.append(aug_image)
    else:
        print(f"  {label}: using {TARGET_PER_CLASS} real images")

    return selected_real, synthetic_tensors


def write_split(label, real_paths, synthetic_tensors):
    rng = random.Random(SEED + hash(label))
    shuffled_real = list(real_paths)
    rng.shuffle(shuffled_real)

    val_paths = shuffled_real[:VAL_COUNT]
    test_paths = shuffled_real[VAL_COUNT:VAL_COUNT + TEST_COUNT]
    train_real_paths = shuffled_real[VAL_COUNT + TEST_COUNT:]

    for split in ("train", "val", "test"):
        os.makedirs(os.path.join(OUTPUT_DIR, split, label), exist_ok=True)

    val_dir = os.path.join(OUTPUT_DIR, "val", label)
    for index, src in enumerate(val_paths):
        ext = os.path.splitext(src)[1].lower()
        dst = os.path.join(val_dir, f"{label}_val_{index:04d}{ext}")
        shutil.copy2(src, dst)

    test_dir = os.path.join(OUTPUT_DIR, "test", label)
    for index, src in enumerate(test_paths):
        ext = os.path.splitext(src)[1].lower()
        dst = os.path.join(test_dir, f"{label}_test_{index:04d}{ext}")
        shutil.copy2(src, dst)

    train_dir = os.path.join(OUTPUT_DIR, "train", label)
    for index, src in enumerate(train_real_paths):
        ext = os.path.splitext(src)[1].lower()
        dst = os.path.join(train_dir, f"{label}_train_real_{index:04d}{ext}")
        shutil.copy2(src, dst)

    for index, tensor in enumerate(synthetic_tensors):
        dst = os.path.join(train_dir, f"{label}_train_synth_{index:04d}.jpg")
        save_image(tensor, dst)

    train_total = len(train_real_paths) + len(synthetic_tensors)
    return {
        "train": train_total,
        "val": len(val_paths),
        "test": len(test_paths),
        "total": train_total + len(val_paths) + len(test_paths),
    }


def main():
    print("=" * 64)
    print("  TomoLeafNet Detector Dataset Preparation")
    print("=" * 64)
    print(f"Source: {SOURCE_DIR}")
    print(f"Output: {OUTPUT_DIR}")
    print()

    if os.path.exists(OUTPUT_DIR):
        shutil.rmtree(OUTPUT_DIR)

    tomato_paths = gather_tomato_paths()
    not_tomato_paths = gather_not_tomato_paths()

    pools = {
        "tomato_leaf": build_class_pool("tomato_leaf", tomato_paths),
        "not_tomato_leaf": build_class_pool("not_tomato_leaf", not_tomato_paths),
    }

    summary = {}
    for label, (real_paths, synthetic_tensors) in pools.items():
        summary[label] = write_split(label, real_paths, synthetic_tensors)
        assert summary[label]["train"] == TRAIN_COUNT
        assert summary[label]["val"] == VAL_COUNT
        assert summary[label]["test"] == TEST_COUNT
        assert summary[label]["total"] == TARGET_PER_CLASS

    print()
    for label in ("tomato_leaf", "not_tomato_leaf"):
        stats = summary[label]
        print(
            f"OK {label:16s}: {stats['total']} images "
            f"(train={stats['train']} | val={stats['val']} | test={stats['test']})"
        )

    print("Dataset ready for binary detector training.")
    print("=" * 64)


if __name__ == "__main__":
    main()
