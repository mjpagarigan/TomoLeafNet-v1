import os
import sys
import numpy as np
import tensorflow as tf
import matplotlib
matplotlib.use('Agg')  # Non-interactive backend for saving plots
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.metrics import confusion_matrix, classification_report

# Import shared model utilities
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'SCRIPTS'))
from model_utils import load_model as load_custom_model, CLASS_NAMES

# --- PATHS (relative to project root) ---
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATASET_PATH = os.path.join(BASE_DIR, 'DATA-LABEL')
RESULTS_DIR = os.path.dirname(os.path.abspath(__file__))
LIMIT_PER_CLASS = 1000

# Must match the model's output layer order (alphabetical from training)
ALL_5_CLASSES = [
    "Bacterial_Spot", "Early_Blight",
    "Healthy", "Late_Blight", "Septoria"
]

# --- EVALUATION ---

model = load_custom_model()

y_true, y_pred = [], []

print(f"🚀 Running 5-class evaluation on DATA-LABEL folders...")

for label_idx, label_name in enumerate(ALL_5_CLASSES):
    folder_path = os.path.join(DATASET_PATH, label_name)

    if not os.path.exists(folder_path):
        print(f"   ⚠️  Skipping {label_name}: folder not found")
        continue

    images = [f for f in os.listdir(folder_path) 
              if f.lower().endswith(('.png', '.jpg', '.jpeg')) and not f.startswith('._')]
    print(f"   📁 {label_name}: testing {min(len(images), LIMIT_PER_CLASS)} images...")
    
    for name in images[:LIMIT_PER_CLASS]:
        try:
            img = tf.keras.utils.load_img(os.path.join(folder_path, name), target_size=(224, 224))
            arr = tf.keras.utils.img_to_array(img)
            p = model.predict(np.expand_dims(arr, 0), verbose=0)
            y_pred.append(np.argmax(p[0]))
            y_true.append(label_idx)
        except Exception:
            continue  # Skip corrupt or unreadable files

# --- CLASSIFICATION REPORT ---

present_indices = np.unique(y_true)
present_names = [ALL_5_CLASSES[i] for i in present_indices]

report = classification_report(
    y_true,
    y_pred,
    labels=present_indices,
    target_names=present_names,
    output_dict=True
)

# Print text report
report_text = classification_report(
    y_true,
    y_pred,
    labels=present_indices,
    target_names=present_names
)

print("\n" + "=" * 70)
print(f"{'CLASSIFICATION REPORT':^70}")
print("=" * 70)
print(report_text)
print("=" * 70)

# --- CONFUSION MATRIX ---

cm = confusion_matrix(y_true, y_pred, labels=range(5))

plt.figure(figsize=(10, 8))
sns.heatmap(cm, annot=True, fmt='d', cmap='Greens',
            xticklabels=ALL_5_CLASSES, yticklabels=ALL_5_CLASSES)
plt.title("TomoLeafNet v3: 5-Class Confusion Matrix")
plt.xlabel("Predicted Label")
plt.ylabel("True Label")
plt.tight_layout()

save_path = os.path.join(RESULTS_DIR, 'ConfusionMatrix.png')
plt.savefig(save_path, dpi=150)
print(f"\n✅ Confusion matrix saved to: {save_path}")
plt.close()