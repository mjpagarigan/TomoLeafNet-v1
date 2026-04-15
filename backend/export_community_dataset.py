"""
Export approved community contributions from Firebase into class folders.

Usage:
    python export_community_dataset.py --output-dir community_export

Environment:
    GOOGLE_APPLICATION_CREDENTIALS  Path to a Firebase service account JSON
    FIREBASE_STORAGE_BUCKET         Optional explicit storage bucket name
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore, storage


def initialize_firebase() -> firestore.Client:
    if firebase_admin._apps:
        return firestore.client()

    bucket_name = os.getenv("FIREBASE_STORAGE_BUCKET")
    options = {"storageBucket": bucket_name} if bucket_name else None

    firebase_admin.initialize_app(credentials.ApplicationDefault(), options)
    return firestore.client()


def ensure_directory(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def export_dataset(output_dir: Path) -> None:
    db = initialize_firebase()
    bucket = storage.bucket()

    ensure_directory(output_dir)

    query = (
        db.collection("community_contributions")
        .where("isApprovedForTraining", "==", True)
        .stream()
    )

    counts: dict[str, int] = {
        "Early_Blight": 0,
        "Leaf_Mold": 0,
        "Leaf_Miner": 0,
        "Healthy": 0,
    }

    for doc in query:
        data = doc.to_dict()
        predicted_disease = data.get("predictedDisease")
        image_storage_path = data.get("imageStoragePath")

        if predicted_disease not in counts:
            continue
        if not image_storage_path:
            continue

        target_dir = output_dir / predicted_disease
        ensure_directory(target_dir)

        blob = bucket.blob(image_storage_path)
        file_name = f"{doc.id}{Path(image_storage_path).suffix or '.jpg'}"
        blob.download_to_filename(str(target_dir / file_name))
        counts[predicted_disease] += 1

    total = sum(counts.values())

    print("Approved contributions ready for training:")
    print(f"Early_Blight : {counts['Early_Blight']} images")
    print(f"Leaf_Mold    : {counts['Leaf_Mold']} images")
    print(f"Leaf_Miner   : {counts['Leaf_Miner']} images")
    print(f"Healthy      : {counts['Healthy']} images")
    print(f"Total        : {total} images")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Export approved community contributions for retraining.",
    )
    parser.add_argument(
        "--output-dir",
        default="community_export",
        help="Directory where exported class folders will be created.",
    )
    args = parser.parse_args()

    export_dataset(Path(args.output_dir))


if __name__ == "__main__":
    main()
