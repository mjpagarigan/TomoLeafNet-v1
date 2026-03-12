import cv2
import numpy as np
import os
import sys
import time
import tensorflow as tf

# Import shared model utilities
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from model_utils import load_model, CLASS_NAMES

# --- CONFIG ---
MODEL_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'MODEL', 'tomoleafnet_v3_hybrid.h5')

# --- INITIALIZE ---
class_names = CLASS_NAMES
model = load_model(MODEL_PATH)

cap = cv2.VideoCapture(0)
# Set resolution for better performance
cap.set(3, 640) 
cap.set(4, 480)

print("Live Camera Active. Align leaf in the center box. Press 'Q' to exit.")

while True:
    ret, frame = cap.read()
    if not ret: break

    # Center crop logic (224x224 to match model input)
    h, w, _ = frame.shape
    size = 224
    x1, y1 = (w - size) // 2, (h - size) // 2
    x2, y2 = x1 + size, y1 + size

    # 1. Preprocess: Crop -> RGB -> Float
    crop = frame[y1:y2, x1:x2]
    rgb = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)
    # Model expects 0-255 float based on your training script
    blob = np.expand_dims(rgb.astype(np.float32), axis=0)

    # 2. Inference
    t1 = time.time()
    preds = model.predict(blob, verbose=0)[0]
    # Apply softmax to get percentages
    scores = tf.nn.softmax(preds).numpy()
    fps = 1.0 / (time.time() - t1)

    # 3. Interpret
    idx = np.argmax(scores)
    label = class_names[idx].replace("Tomato_", "")
    conf = scores[idx] * 100

    # 4. UI Drawing
    color = (0, 255, 0) if conf > 80 else (0, 255, 255) if conf > 50 else (0, 0, 255)
    
    cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
    cv2.putText(frame, f"{label}: {conf:.1f}%", (x1, y1-10), 
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)
    cv2.putText(frame, f"FPS: {fps:.1f}", (10, 30), 
                cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)

    cv2.imshow('TomoLeafNet Live', frame)

    if cv2.waitKey(1) & 0xFF == ord('q'): break

cap.release()
cv2.destroyAllWindows()