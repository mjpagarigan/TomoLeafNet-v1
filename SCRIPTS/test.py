import os
import sys
import numpy as np
import matplotlib.pyplot as plt

# Import shared model utilities
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from model_utils import load_model, CLASS_NAMES

# --- CONFIG ---

# ✅ PASTE THE PATH TO YOUR TEST IMAGE HERE
IMG_PATH = r''

# --- SETUP ---

print("⏳ Setting up...")
class_names = CLASS_NAMES
print(f"✅ Detected Classes: {class_names}")

model = load_model()


# --- PREDICTION ---

def predict_image(image_path):
    import tensorflow as tf
    print(f"\n🔍 Analyzing: {os.path.basename(image_path)}")
    
    # 1. Load Image (original size)
    img = tf.keras.utils.load_img(image_path)
    img_array = tf.keras.utils.img_to_array(img)
    
    # 2. Smart Preprocessing: Center crop to square, then resize
    # Matches training augmentation and prevents aspect ratio distortion
    h, w, _ = img_array.shape
    min_dim = min(h, w)
    
    start_h = (h - min_dim) // 2
    start_w = (w - min_dim) // 2
    img_cropped = img_array[start_h:start_h+min_dim, start_w:start_w+min_dim, :]
    
    img_resized = tf.image.resize(img_cropped, (224, 224))
    img_array = np.expand_dims(img_resized, 0)
    
    # Update image for display so we see what the model sees
    img = tf.keras.utils.array_to_img(img_resized)
    
    # 3. Run Prediction
    predictions = model.predict(img_array, verbose=0)

    # 4. Extract Results
    predicted_class = class_names[np.argmax(predictions[0])]
    confidence = 100 * np.max(predictions[0])
    
    return img, predicted_class, confidence, predictions[0]

# Run the function
img, pred_class, conf, all_probs = predict_image(IMG_PATH)


# --- DISPLAY RESULTS ---

print("\n" + "="*30)
print(f"🌿 DIAGNOSIS REPORT")
print("="*30)
print(f"👉 RESULT:     {pred_class}")
print(f"💪 CONFIDENCE: {conf:.2f}%")
print("-" * 30)
print("📊 Full Breakdown:")
for i, prob in enumerate(all_probs):
    print(f"   - {class_names[i]}: {prob*100:.2f}%")
print("="*30)

# Show Image
plt.figure(figsize=(6, 6))
plt.imshow(img)
plt.axis('off')

# Color logic: Green if confident (>80%), Yellow if unsure
text_color = 'darkgreen' if conf > 80 else 'darkorange'

plt.title(f"Prediction: {pred_class}\nConfidence: {conf:.2f}%", 
          color='white', backgroundcolor=text_color, fontweight='bold', fontsize=14)

plt.tight_layout()
plt.show()