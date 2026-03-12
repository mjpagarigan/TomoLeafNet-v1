import os
import sys
import random
import numpy as np
import cv2
import matplotlib.pyplot as plt

# Import shared model utilities
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'SCRIPTS'))
from model_utils import load_model, CLASS_NAMES, DATA_LABEL_DIR

# 1. CONFIGURATION

DATASET_PATH = DATA_LABEL_DIR

# Class names from shared model utilities
CLASS_NAMES_LOCAL = CLASS_NAMES

# Grid Settings
ROWS = 2
COLS = 4
NUM_IMAGES = ROWS * COLS

# 2. HELPER FUNCTIONS


def load_and_preprocess_image(img_path):
    """Loads an image using OpenCV and prepares it for the model."""
    # Read image (BGR)
    img = cv2.imread(img_path)
    # Convert to RGB
    img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    # Resize to model input size
    img_resized = cv2.resize(img, (224, 224))
    # Normalize/Convert to float (if your model expects 0-255, remove /255.0)
    # Usually standard models expect 0-255 input if no scaling layer is included, 
    # but strictly ensures float32 format.
    img_array = img_resized.astype('float32')
    # Add batch dimension (1, 224, 224, 3)
    img_expanded = np.expand_dims(img_array, axis=0)
    return img, img_expanded

def get_random_samples(dataset_path, num_samples):
    """Picks random images from the dataset folders."""
    all_images = []
    
    # Scan all class folders
    for label in os.listdir(dataset_path):
        class_dir = os.path.join(dataset_path, label)
        if os.path.isdir(class_dir):
            for file in os.listdir(class_dir):
                if file.lower().endswith(('.png', '.jpg', '.jpeg')):
                    all_images.append((os.path.join(class_dir, file), label))
    
    # Shuffle and pick N samples
    if len(all_images) < num_samples:
        return all_images # Return all if less than requested
    return random.sample(all_images, num_samples)


# 3. MAIN SCRIPT


print("⏳ Loading Model...")
model = load_model()


# Get random images
samples = get_random_samples(DATASET_PATH, NUM_IMAGES)

# Setup Plot
fig, axes = plt.subplots(ROWS, COLS, figsize=(16, 8))
fig.suptitle(f"TomoLeafNet Random Batch Test ({NUM_IMAGES} Samples)", fontsize=16, fontweight='bold')

# Flatten axes for easy looping
axes = axes.flatten()

for i, (img_path, true_label) in enumerate(samples):
    ax = axes[i]
    
    # 1. Process Image
    original_img, input_tensor = load_and_preprocess_image(img_path)
    
    # 2. Predict
    predictions = model.predict(input_tensor, verbose=0)
    pred_idx = np.argmax(predictions[0])
    confidence = np.max(predictions[0]) * 100
    pred_label = CLASS_NAMES_LOCAL[pred_idx]
    
    # 3. Determine Status (MATCH or MISS)
    if true_label == pred_label:
        status = "MATCH"
        color = "green"
        icon = "✅"
    else:
        status = "MISS"
        color = "red"
        icon = "❌"

    # 4. Display Image
    ax.imshow(original_img)
    ax.axis('off') # Hide axis ticks

    # 5. Create Text Box Overlay
    text_str = (
        f"{icon} {status}\n"
        f"True: {true_label}\n"
        f"Pred: {pred_label}\n"
        f"Conf: {confidence:.1f}%"
    )
    
    # Add text box in bottom-left corner
    ax.text(
        0.05, 0.05, text_str, 
        transform=ax.transAxes, 
        fontsize=10, 
        fontweight='bold',
        color='black',
        verticalalignment='bottom', 
        bbox=dict(boxstyle="round,pad=0.5", facecolor="white", alpha=0.85, edgecolor=color, linewidth=2)
    )

# Hide unused subplots if samples < grid size
for j in range(len(samples), NUM_IMAGES):
    axes[j].axis('off')

plt.tight_layout()
plt.subplots_adjust(top=0.9) # Make room for title
plt.show()