import os
import sys
import numpy as np
import tensorflow as tf
from tensorflow.keras import layers, models, callbacks, optimizers

# Import shared custom layers
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from model_utils import SpatialAttention, TransformerBlock

# --- PATHS (relative to project root) ---
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(BASE_DIR, 'DATA-SPLIT')
SAVE_PATH = os.path.join(BASE_DIR, 'MODEL', 'tomoleafnet_v3_hybrid.keras')
TFLITE_PATH = os.path.join(BASE_DIR, 'MODEL', 'tomoleafnet_v3.tflite')

LOAD_SIZE = (400, 400)
IMG_SIZE = (224, 224)
BATCH = 32

# --- DATA LOAD & AUGMENT ---

print("📂 Loading training data...")
train_ds = tf.keras.utils.image_dataset_from_directory(
    os.path.join(DATA_DIR, 'train'),
    image_size=LOAD_SIZE, batch_size=BATCH, label_mode='categorical'
)

print("📂 Loading validation data...")
val_ds = tf.keras.utils.image_dataset_from_directory(
    os.path.join(DATA_DIR, 'val'),
    image_size=LOAD_SIZE, batch_size=BATCH, label_mode='categorical'
)

class_names = train_ds.class_names
print(f"✅ Classes: {class_names}")
print(f"✅ Number of classes: {len(class_names)}")

# Center crop for validation, random crop for training
train_ds = train_ds.map(lambda x, y: (tf.image.random_crop(x, size=(tf.shape(x)[0], IMG_SIZE[0], IMG_SIZE[1], 3)), y))
val_ds = val_ds.map(lambda x, y: (tf.image.resize_with_crop_or_pad(x, IMG_SIZE[0], IMG_SIZE[1]), y))

# Data augmentation (aggressive — simulate real-world mobile captures)
augment = tf.keras.Sequential([
    layers.RandomFlip("horizontal_and_vertical"), # phone photos come at any orientation
    layers.RandomRotation(0.25),                  # +/-45 deg (phone held at various angles)
    layers.RandomZoom((-0.3, 0.15)),              # wider zoom range (variable capture distance)
    layers.RandomTranslation(0.2, 0.2),           # leaf often off-center in real photos
    layers.RandomContrast(0.3),                   # outdoor lighting varies significantly
    layers.RandomBrightness(0.3),                 # shadows and direct sunlight
    layers.GaussianNoise(0.15),                   # camera sensor noise + compression artifacts
])

# --- BUILDING THE HYBRID MODEL ---

print("\n🏗️  Building hybrid model (MobileNetV3Small + Attention + Transformer)...")

# MobileNetV3Small base for mobile efficiency
base = tf.keras.applications.MobileNetV3Small(
    input_shape=(224, 224, 3), include_top=False, weights='imagenet'
)

inputs = layers.Input(shape=(224, 224, 3))
x = augment(inputs)
x = base(x)

# Apply spatial attention
x = SpatialAttention()(x)

# Prep for Transformer (flatten spatial dimensions)
x = layers.Conv2D(128, 1)(x)
x = layers.BatchNormalization()(x)
s = x.shape
x = layers.Reshape((s[1] * s[2], s[3]))(x)
x = TransformerBlock()(x)

x = layers.GlobalAveragePooling1D()(x)
x = layers.Dropout(0.4)(x)
x = layers.Dense(64, activation='relu',
    kernel_regularizer=tf.keras.regularizers.l2(1e-4))(x)
x = layers.Dropout(0.3)(x)
out = layers.Dense(len(class_names), activation='softmax')(x)

model = models.Model(inputs, out)

print(f"✅ Model built. Output classes: {len(class_names)}")
model.summary()

# --- TRAINING ---

# Phase 1: Train only the new head (base frozen)
print("\n🔒 Phase 1: Training classification head (base frozen)...")
base.trainable = False

METRICS = [
    tf.keras.metrics.CategoricalAccuracy(name='accuracy'),
    tf.keras.metrics.AUC(name='auc')
]
LOSS = tf.keras.losses.CategoricalCrossentropy(label_smoothing=0.1)

model.compile(
    optimizer=optimizers.Adam(3e-4),  # lower than default 1e-3 for stability
    loss=LOSS, metrics=METRICS
)
history1 = model.fit(train_ds, validation_data=val_ds, epochs=10)

# Phase 2: Fine-tune (unfreeze last 30 base layers)
print("\n🔓 Phase 2: Fine-tuning (last 30 base layers unfrozen)...")
base.trainable = True
for layer in base.layers[:-30]:
    layer.trainable = False

# Use fixed LR with ReduceLROnPlateau for dynamic adjustment
# (CosineDecay schedules are incompatible with ReduceLROnPlateau in TF 2.10)
model.compile(
    optimizer=optimizers.Adam(5e-5),
    loss=LOSS, metrics=METRICS
)

history2 = model.fit(train_ds, validation_data=val_ds, epochs=25, callbacks=[
    callbacks.EarlyStopping(monitor='val_auc', patience=7, restore_best_weights=True, mode='max'),
    callbacks.ModelCheckpoint(SAVE_PATH, monitor='val_auc', save_best_only=True, mode='max'),
    callbacks.ReduceLROnPlateau(
        monitor='val_auc', factor=0.5, patience=3, min_lr=1e-7, verbose=1, mode='max'
    ),
])

print(f"\n✅ Training complete. Model saved to: {SAVE_PATH}")

# --- PLOT TRAINING HISTORY ---
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

RESULTS_DIR = os.path.join(BASE_DIR, 'RESULTS')
os.makedirs(RESULTS_DIR, exist_ok=True)

# Combine Phase 1 + Phase 2 histories
loss = history1.history['loss'] + history2.history['loss']
val_loss = history1.history['val_loss'] + history2.history['val_loss']
acc = history1.history['accuracy'] + history2.history['accuracy']
val_acc = history1.history['val_accuracy'] + history2.history['val_accuracy']
auc = history1.history['auc'] + history2.history['auc']
val_auc = history1.history['val_auc'] + history2.history['val_auc']
epochs = range(1, len(loss) + 1)
phase1_end = len(history1.history['loss'])

fig, axes = plt.subplots(1, 3, figsize=(18, 5))
ax1, ax2, ax3 = axes

# Loss
ax1.plot(epochs, loss, 'b-', label='Train Loss')
ax1.plot(epochs, val_loss, 'r-', label='Val Loss')
ax1.axvline(x=phase1_end, color='gray', linestyle='--', alpha=0.6, label='Fine-tune Start')
ax1.set_title('Training & Validation Loss', fontweight='bold')
ax1.set_xlabel('Epoch')
ax1.set_ylabel('Loss')
ax1.legend()
ax1.grid(True, alpha=0.3)

# Accuracy
ax2.plot(epochs, acc, 'b-', label='Train Accuracy')
ax2.plot(epochs, val_acc, 'r-', label='Val Accuracy')
ax2.axvline(x=phase1_end, color='gray', linestyle='--', alpha=0.6, label='Fine-tune Start')
ax2.set_title('Training & Validation Accuracy', fontweight='bold')
ax2.set_xlabel('Epoch')
ax2.set_ylabel('Accuracy')
ax2.legend()
ax2.grid(True, alpha=0.3)

# AUC
ax3.plot(epochs, auc, 'b-', label='Train AUC')
ax3.plot(epochs, val_auc, 'r-', label='Val AUC')
ax3.axvline(x=phase1_end, color='gray', linestyle='--', alpha=0.6, label='Fine-tune Start')
ax3.set_title('Training & Validation AUC', fontweight='bold')
ax3.set_xlabel('Epoch')
ax3.set_ylabel('AUC')
ax3.legend()
ax3.grid(True, alpha=0.3)

plt.suptitle('TomoLeafNet v3 Training History', fontsize=14, fontweight='bold')
plt.tight_layout()

history_path = os.path.join(RESULTS_DIR, 'TrainingHistory.png')
plt.savefig(history_path, dpi=150)
plt.close()
print(f"📊 Training history saved to: {history_path}")

# Save raw history data as JSON for re-plotting later
import json
history_data = {
    'loss': loss, 'val_loss': val_loss,
    'accuracy': acc, 'val_accuracy': val_acc,
    'auc': auc, 'val_auc': val_auc,
    'phase1_epochs': phase1_end
}
json_path = os.path.join(RESULTS_DIR, 'training_history.json')
with open(json_path, 'w') as f:
    json.dump(history_data, f, indent=2)
print(f"📊 Training history data saved to: {json_path}")

# --- CONVERT TO TFLITE ---
print("\n📱 Converting to TFLite for Android...")
try:
    # Reload the saved model to ensure clean conversion
    from model_utils import load_model
    saved_model = load_model(SAVE_PATH)
    convert = tf.lite.TFLiteConverter.from_keras_model(saved_model)
    convert.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = convert.convert()

    with open(TFLITE_PATH, 'wb') as f:
        f.write(tflite_model)

    print(f"✅ TFLite model saved to: {TFLITE_PATH}")
    print(f"   .h5 size:    {os.path.getsize(SAVE_PATH) / 1024 / 1024:.1f} MB")
    print(f"   .tflite size: {os.path.getsize(TFLITE_PATH) / 1024 / 1024:.1f} MB")
except Exception as e:
    print(f"⚠️  TFLite conversion failed: {e}")
    print(f"   The .h5 model was saved successfully and can still be used.")
    print(f"   You can convert to TFLite separately later.")

print("\n🎉 Done. Model ready for deployment.")