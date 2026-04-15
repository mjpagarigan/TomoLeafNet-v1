"""
0_augment_field_dataset.py — Field Dataset Balancer & Splitter

Reads raw field-captured images, augments each class to exactly 1,000 images,
then performs a stratified 70/15/15 split into train/val/test.

IMPORTANT: Only the training split receives augmented (synthetic) images.
Val and test splits contain real images only.

Usage:
    python 0_augment_field_dataset.py
"""

import os
import random
import shutil

import tensorflow as tf
from tensorflow.keras import layers

# ── Paths ─────────────────────────────────────────────────────────────
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
FIELD_RAW_DIR = os.path.join(BASE_DIR, "DATA-RAW", "field")
OUTPUT_DIR = os.path.join(BASE_DIR, "DATA-SPLIT", "target_field")

CLASS_NAMES = ["Early_Blight", "Healthy", "Leaf_Miner", "Leaf_Mold", "Not_Tomato"]
TARGET_PER_CLASS = 1000
IMG_SIZE = 224
SEED = 42

# ── Augmentation pipeline ─────────────────────────────────────────────
augment = tf.keras.Sequential([
    layers.RandomFlip("horizontal_and_vertical"),
    layers.RandomRotation(0.25),
    layers.RandomZoom((-0.3, 0.15)),
    layers.RandomTranslation(0.2, 0.2),
    layers.RandomContrast(0.3),
    layers.RandomBrightness(0.3),
])

VALID_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp"}


def list_images(folder):
    """Return sorted list of image file paths in a folder."""
    files = []
    for f in os.listdir(folder):
        if os.path.splitext(f)[1].lower() in VALID_EXTENSIONS:
            files.append(os.path.join(folder, f))
    files.sort()
    return files


def load_and_resize(path):
    """Load an image file, decode, and resize to IMG_SIZE x IMG_SIZE."""
    raw = tf.io.read_file(path)
    img = tf.image.decode_image(raw, channels=3, expand_animations=False)
    img = tf.image.resize(img, [IMG_SIZE, IMG_SIZE])
    return img


def save_image(tensor, path):
    """Save a float32 tensor as a JPEG file."""
    img = tf.cast(tf.clip_by_value(tensor, 0, 255), tf.uint8)
    encoded = tf.io.encode_jpeg(img, quality=95)
    tf.io.write_file(path, encoded)


def augment_class(raw_folder, class_name):
    """
    Load all real images for a class. Generate synthetic images via
    augmentation until total reaches TARGET_PER_CLASS.

    Returns:
        real_paths: list of original image file paths
        synthetic_tensors: list of augmented image tensors
    """
    image_paths = list_images(raw_folder)
    num_real = len(image_paths)
    num_synthetic_needed = TARGET_PER_CLASS - num_real

    print(f"  {class_name}: {num_real} real", end="")

    if num_synthetic_needed <= 0:
        print(f" (already >= {TARGET_PER_CLASS}, using first {TARGET_PER_CLASS})")
        return image_paths[:TARGET_PER_CLASS], []

    print(f" + {num_synthetic_needed} synthetic = {TARGET_PER_CLASS} total")

    # Load all real images into memory for augmentation
    real_images = [load_and_resize(p) for p in image_paths]

    synthetic_tensors = []
    rng = random.Random(SEED + hash(class_name))
    for i in range(num_synthetic_needed):
        # Pick a random real image as the source
        src_idx = rng.randint(0, num_real - 1)
        src_img = real_images[src_idx]
        # Apply augmentation (add batch dim, then remove)
        aug_img = augment(tf.expand_dims(src_img, 0), training=True)[0]
        synthetic_tensors.append(aug_img)

    return image_paths, synthetic_tensors


def stratified_split(real_paths, synthetic_tensors, class_name, output_dir):
    """
    Split images into train/val/test with 70/15/15 ratio.
    Val and test get ONLY real images. Synthetic goes to train only.

    For 1,000 total: train=700, val=150, test=150.
    Real images: shuffle, take first 150 for val, next 150 for test,
                 remaining real go to train.
    All synthetic images go to train.
    """
    rng = random.Random(SEED + hash(class_name))
    shuffled_real = list(real_paths)
    rng.shuffle(shuffled_real)

    num_val = 150
    num_test = 150

    val_paths = shuffled_real[:num_val]
    test_paths = shuffled_real[num_val:num_val + num_test]
    train_real_paths = shuffled_real[num_val + num_test:]

    # Create output directories
    for split in ["train", "val", "test"]:
        split_dir = os.path.join(output_dir, split, class_name)
        os.makedirs(split_dir, exist_ok=True)

    # Copy val images (real only)
    val_dir = os.path.join(output_dir, "val", class_name)
    for i, src in enumerate(val_paths):
        ext = os.path.splitext(src)[1]
        dst = os.path.join(val_dir, f"{class_name}_val_{i:04d}{ext}")
        shutil.copy2(src, dst)

    # Copy test images (real only)
    test_dir = os.path.join(output_dir, "test", class_name)
    for i, src in enumerate(test_paths):
        ext = os.path.splitext(src)[1]
        dst = os.path.join(test_dir, f"{class_name}_test_{i:04d}{ext}")
        shutil.copy2(src, dst)

    # Copy real training images
    train_dir = os.path.join(output_dir, "train", class_name)
    idx = 0
    for src in train_real_paths:
        ext = os.path.splitext(src)[1]
        dst = os.path.join(train_dir, f"{class_name}_train_real_{idx:04d}{ext}")
        shutil.copy2(src, dst)
        idx += 1

    # Save synthetic training images
    for j, tensor in enumerate(synthetic_tensors):
        dst = os.path.join(train_dir, f"{class_name}_train_synth_{j:04d}.jpg")
        save_image(tensor, dst)

    num_train = len(train_real_paths) + len(synthetic_tensors)
    return num_train, len(val_paths), len(test_paths)


def main():
    print("=" * 60)
    print("  Field Dataset Augmentation & Split")
    print("=" * 60)
    print(f"\nSource:  {FIELD_RAW_DIR}")
    print(f"Output:  {OUTPUT_DIR}")
    print(f"Target:  {TARGET_PER_CLASS} images per class")
    print()

    # Clean output directory
    if os.path.exists(OUTPUT_DIR):
        shutil.rmtree(OUTPUT_DIR)
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    total_train = 0
    total_val = 0
    total_test = 0

    print("-- Augmenting classes --")
    for class_name in CLASS_NAMES:
        raw_folder = os.path.join(FIELD_RAW_DIR, class_name)
        if not os.path.isdir(raw_folder):
            print(f"  WARNING: Folder not found: {raw_folder}")
            continue

        real_paths, synthetic_tensors = augment_class(raw_folder, class_name)

        print(f"  Splitting {class_name} into train/val/test...")
        n_train, n_val, n_test = stratified_split(
            real_paths, synthetic_tensors, class_name, OUTPUT_DIR
        )
        total_train += n_train
        total_val += n_val
        total_test += n_test

    print()
    print("-- Summary --")
    num_real = {
        "Early_Blight": 377,
        "Healthy": 902,
        "Leaf_Miner": 560,
        "Leaf_Mold": 386,
        "Not_Tomato": 500,
    }
    for cls in CLASS_NAMES:
        real = num_real.get(cls, 0)
        synth = TARGET_PER_CLASS - real
        print(f"  {cls:15s}: {real} real + {synth} synthetic = {TARGET_PER_CLASS} total")

    print(f"\n  Split complete: train={total_train} | val={total_val} | test={total_test}")
    print("=" * 60)
    print("Done! Output saved to:", OUTPUT_DIR)


if __name__ == "__main__":
    main()
