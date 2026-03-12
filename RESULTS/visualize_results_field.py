import os
import sys
import numpy as np
import cv2
import matplotlib.pyplot as plt

# Import shared model utilities
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'SCRIPTS'))
from model_utils import load_model, CLASS_NAMES

# 1. CONFIGURATION

# Class names from shared model utilities
CLASS_NAMES_LOCAL = CLASS_NAMES

# ✅ PASTE YOUR PATHS AND LABELS HERE
# Format: ( r'PATH_TO_IMAGE', "EXACT_CLASS_NAME" )
TEST_DATA = [
    (r'/Users/mj/Downloads/test_img1.jpg', "Healthy"),
    (r'/Users/mj/Downloads/test_img2.jpg', "Bacterial_Spot"),
    (r'/Users/mj/Downloads/test_img4.jpg', "Early_Blight"),
    (r'/Users/mj/Downloads/test_img6.jpg', "Late_Blight"),
    (r'/Users/mj/Downloads/test_img8.jpg', "Septoria")
]
# ----------------------------------------

# Grid Settings
ROWS = 1
COLS = 5
NUM_IMAGES = len(TEST_DATA)

# 2. HELPER FUNCTIONS

def load_and_preprocess_image(img_path):
    """Loads an image using OpenCV and prepares it for the model."""
    if not os.path.exists(img_path):
        return None, None
        
    img = cv2.imread(img_path)
    if img is None:
        return None, None

    img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    img_resized = cv2.resize(img, (224, 224))
    img_array = img_resized.astype('float32')
    img_expanded = np.expand_dims(img_array, axis=0)
    return img, img_expanded

# 3. MAIN SCRIPT

print("⏳ Loading Model...")
model = load_model()


# Setup Plot
fig, axes = plt.subplots(ROWS, COLS, figsize=(20, 5))
fig.suptitle(f"TomoLeafNet Manual Verification ({NUM_IMAGES} Samples)", fontsize=16, fontweight='bold')

# Flatten axes for easy looping
if NUM_IMAGES == 1:
    axes = [axes]
else:
    axes = axes.flatten()

for i, (img_path, true_label) in enumerate(TEST_DATA):
    # Stop if we run out of subplot slots
    if i >= len(axes): break
    
    ax = axes[i]
    
    # 1. Process Image
    original_img, input_tensor = load_and_preprocess_image(img_path)
    
    # Handle bad paths
    if original_img is None:
        ax.text(0.5, 0.5, "Image Not Found\nCheck Path", 
                horizontalalignment='center', verticalalignment='center')
        ax.axis('off')
        continue

    # 2. Predict
    predictions = model.predict(input_tensor, verbose=0)
    pred_idx = np.argmax(predictions[0])
    confidence = np.max(predictions[0]) * 100
    pred_label = CLASS_NAMES_LOCAL[pred_idx]
    
    # 3. Compare (True vs Pred)
    if true_label == pred_label:
        status = "MATCH"
        color = "green"
        icon = "✅"
        box_edge = "green"
    else:
        status = "MISS"
        color = "red"
        icon = "❌"
        box_edge = "red"

    # 4. Display Image
    ax.imshow(original_img)
    ax.axis('off')

    # 5. Create Text Box Overlay
    text_str = (
        f"{icon} {status}\n"
        f"True: {true_label}\n"
        f"Pred: {pred_label}\n"
        f"Conf: {confidence:.1f}%"
    )
    
    # Add text box
    ax.text(
        0.05, 0.05, text_str, 
        transform=ax.transAxes, 
        fontsize=10, 
        fontweight='bold',
        color='black',
        verticalalignment='bottom', 
        bbox=dict(boxstyle="round,pad=0.5", facecolor="white", alpha=0.9, edgecolor=box_edge, linewidth=2)
    )

# Hide unused subplots
for j in range(NUM_IMAGES, len(axes)):
    axes[j].axis('off')

plt.tight_layout()
plt.subplots_adjust(top=0.9)
plt.show()