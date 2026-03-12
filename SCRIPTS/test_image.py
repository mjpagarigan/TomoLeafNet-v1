import os
import sys
import numpy as np
import matplotlib.pyplot as plt

# Import shared model utilities
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'SCRIPTS'))
from model_utils import load_model, CLASS_NAMES

# --- CONFIG ---
# ✅ PASTE THE PATH TO YOUR TEST IMAGE HERE
IMG_PATH = r'C:\Users\iamha\Downloads\Healthy\Healthy\IMG_20260303_180747.jpg'

# --- INITIALIZE ---s
class_names = CLASS_NAMES
model = load_model()

def run_test(path):
    import tensorflow as tf
    
    # 1. Load image (original size)
    img = tf.keras.utils.load_img(path)
    img_array = tf.keras.utils.img_to_array(img)
    
    # 2. Smart Preprocessing: Center crop to square, then resize
    # This matches the "zoom" augmentation and prevents distortion
    h, w, _ = img_array.shape
    min_dim = min(h, w)
    
    # Center crop
    start_h = (h - min_dim) // 2
    start_w = (w - min_dim) // 2
    img_cropped = img_array[start_h:start_h+min_dim, start_w:start_w+min_dim, :]
    
    # Resize to model input size
    img_resized = tf.image.resize(img_cropped, (224, 224))
    img_array = np.expand_dims(img_resized, axis=0) 

    # 3. Predict
    raw_preds = model.predict(img_array, verbose=0)[0]
    idx = np.argmax(raw_preds)
    
    label = class_names[idx]
    conf = raw_preds[idx] * 100
    
    return img, label, conf, raw_preds

# --- EXECUTE & SHOW ---
img, label, conf, probs = run_test(IMG_PATH)

print(f"\nRESULT: {label}")
print(f"CONFIDENCE: {conf:.2f}%")

# Display with simple plot
plt.imshow(img)
plt.title(f"{label} ({conf:.1f}%)")
plt.axis('off')
plt.show()