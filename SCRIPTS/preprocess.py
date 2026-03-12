import os
import shutil
import random
import cv2
import numpy as np
from tqdm import tqdm

# --- PATHS (relative to project root) ---
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_DIR = os.path.join(BASE_DIR, 'DATA-LABEL')
OUT_DIR = os.path.join(BASE_DIR, 'DATA-SPLIT')
IMG_SIZE = (224, 224)

# Split ratios: 70% train, 15% validation, 15% test
TRAIN_RATIO = 0.70
VAL_RATIO = 0.15
# TEST_RATIO = 0.15 (remainder)

# 5 target disease classes
CLASS_NAMES = [
    'Bacterial_Spot',
    'Early_Blight',
    'Healthy',
    'Late_Blight',
    'Septoria'
]

# Clean output directory
if os.path.exists(OUT_DIR):
    shutil.rmtree(OUT_DIR)
os.makedirs(os.path.join(OUT_DIR, 'train'))
os.makedirs(os.path.join(OUT_DIR, 'val'))
os.makedirs(os.path.join(OUT_DIR, 'test'))

for label in CLASS_NAMES:
    src = os.path.join(RAW_DIR, label)
    if not os.path.isdir(src):
        print(f"[WARNING] Skipping {label}: folder not found")
        continue
    
    os.makedirs(os.path.join(OUT_DIR, 'train', label), exist_ok=True)
    os.makedirs(os.path.join(OUT_DIR, 'val', label), exist_ok=True)
    os.makedirs(os.path.join(OUT_DIR, 'test', label), exist_ok=True)
    
    files = [f for f in os.listdir(src) if f.lower().endswith(('.png', '.jpg', '.jpeg'))]
    random.shuffle(files)
    
    train_end = int(len(files) * TRAIN_RATIO)
    val_end = int(len(files) * (TRAIN_RATIO + VAL_RATIO))
    sets = {
        'train': files[:train_end],
        'val': files[train_end:val_end],
        'test': files[val_end:]
    }

    for mode, items in sets.items():
        for name in tqdm(items, desc=f"{label} -> {mode}"):
            img = cv2.imread(os.path.join(src, name))
            if img is not None:
                img = cv2.resize(img, IMG_SIZE)
                cv2.imwrite(os.path.join(OUT_DIR, mode, label, name), img)

print(f"\n[DONE] Preprocessing complete.")
print(f"   Output: {OUT_DIR}")

# Print summary
for mode in ['train', 'val', 'test']:
    total = 0
    mode_dir = os.path.join(OUT_DIR, mode)
    for label in CLASS_NAMES:
        count = len(os.listdir(os.path.join(mode_dir, label))) if os.path.isdir(os.path.join(mode_dir, label)) else 0
        total += count
        print(f"   {mode}/{label}: {count} images")
    print(f"   {mode} TOTAL: {total}")