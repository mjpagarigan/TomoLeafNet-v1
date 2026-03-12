"""
Convert the .h5 model to .keras format (Keras 3 native).
Since Keras 3 cannot deserialize MobileNetV3's H5 config (hard_sigmoid uses
float positional args to Add/Multiply layers), we rebuild the architecture
from code and load weights by layer name from the H5 file.
"""
import os
import sys
import h5py
import numpy as np
import tensorflow as tf
from tensorflow.keras import layers, models

# Import shared custom layers  
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from model_utils import SpatialAttention, TransformerBlock

# --- PATHS ---
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
H5_PATH = os.path.join(BASE_DIR, 'MODEL', 'tomoleafnet_v3_hybrid.h5')
KERAS_PATH = os.path.join(BASE_DIR, 'MODEL', 'tomoleafnet_v3_hybrid.keras')

NUM_CLASSES = 5

# --- STEP 1: Rebuild exact model architecture ---
print("🏗️  Step 1: Rebuilding model architecture from code...")

augment = tf.keras.Sequential([
    layers.RandomFlip("horizontal_and_vertical"),
    layers.RandomRotation(0.2),
    layers.RandomZoom((-0.2, -0.1)),
    layers.RandomContrast(0.2),
], name='sequential')

base = tf.keras.applications.MobileNetV3Small(
    input_shape=(224, 224, 3), include_top=False, weights='imagenet'
)

inputs = layers.Input(shape=(224, 224, 3))
x = augment(inputs)
x = base(x)
x = SpatialAttention()(x)
x = layers.Conv2D(128, 1)(x)
s = x.shape
x = layers.Reshape((s[1] * s[2], s[3]))(x)
x = TransformerBlock()(x)
x = layers.GlobalAveragePooling1D()(x)
x = layers.Dropout(0.3)(x)
out = layers.Dense(NUM_CLASSES, activation='softmax')(x)

model = models.Model(inputs, out)
print(f"✅ Architecture rebuilt ({model.count_params():,} params)")

# --- STEP 2: Extract weight names from H5 ---
print("⏳ Step 2: Loading weights from H5 by layer name...")

def get_h5_weights(h5_path):
    """Extract all weight data from H5 file by group/layer name."""
    weights = {}
    
    def visitor(name, obj):
        if isinstance(obj, h5py.Dataset):
            weights[name] = np.array(obj)
    
    with h5py.File(h5_path, 'r') as f:
        # Navigate to the weight data
        if 'model_weights' in f:
            f['model_weights'].visititems(visitor)
        else:
            f.visititems(visitor)
    
    return weights

h5_weights = get_h5_weights(H5_PATH)
print(f"   Found {len(h5_weights)} weight arrays in H5 file")

# --- STEP 3: Match and load weights ---
loaded = 0
skipped = 0

for layer in model.layers:
    if not layer.weights:
        continue
    
    # Handle nested models (MobileNetV3Small, Sequential)
    if hasattr(layer, 'layers'):
        for sublayer in layer.layers:
            if not sublayer.weights:
                continue
            for w in sublayer.weights:
                # Try to find matching weight in H5
                w_name = w.name.replace(':0', '')
                matched = False
                for h5_key, h5_val in h5_weights.items():
                    # Match by the variable name (last 2 parts usually match)
                    h5_parts = h5_key.split('/')
                    w_parts = w_name.split('/')
                    
                    # Check if the weight name ends with the same path
                    if len(h5_parts) >= 2 and len(w_parts) >= 2:
                        if h5_parts[-1] == w_parts[-1] and h5_parts[-2] == w_parts[-2]:
                            if h5_val.shape == w.shape:
                                w.assign(h5_val)
                                loaded += 1
                                matched = True
                                break
                    
                    # Direct name match  
                    if h5_key.endswith(w_name) and h5_val.shape == w.shape:
                        w.assign(h5_val)
                        loaded += 1
                        matched = True
                        break
                
                if not matched:
                    skipped += 1
    else:
        for w in layer.weights:
            w_name = w.name.replace(':0', '')
            matched = False
            for h5_key, h5_val in h5_weights.items():
                h5_parts = h5_key.split('/')
                w_parts = w_name.split('/')
                
                if len(h5_parts) >= 2 and len(w_parts) >= 2:
                    if h5_parts[-1] == w_parts[-1] and h5_parts[-2] == w_parts[-2]:
                        if h5_val.shape == w.shape:
                            w.assign(h5_val)
                            loaded += 1
                            matched = True
                            break
                
                if h5_key.endswith(w_name) and h5_val.shape == w.shape:
                    w.assign(h5_val)
                    loaded += 1
                    matched = True
                    break
            
            if not matched:
                skipped += 1

print(f"✅ Loaded {loaded} weight arrays, skipped {skipped}")

if skipped > 0:
    print(f"⚠️  {skipped} weights were not matched. These may be augmentation layers (no trainable weights).")

# --- STEP 4: Save as .keras format ---
print(f"💾 Step 3: Saving as .keras format...")
model.save(KERAS_PATH)
print(f"✅ Conversion complete!")
print(f"   .h5 size:    {os.path.getsize(H5_PATH) / 1024 / 1024:.1f} MB")
print(f"   .keras size: {os.path.getsize(KERAS_PATH) / 1024 / 1024:.1f} MB")
print(f"\n🎉 All scripts will now automatically use the .keras model.")

# Clean up temp file if it exists
fixed_path = os.path.join(BASE_DIR, 'MODEL', 'tomoleafnet_v3_hybrid_fixed.h5')
if os.path.exists(fixed_path):
    os.remove(fixed_path)
