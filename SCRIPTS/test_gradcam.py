"""
Grad-CAM Visualization for TOMOLeafNet
Generates a heatmap showing which regions of the leaf image the model
focused on for its prediction. Uses the last convolutional layer output.

Usage:
    python3 SCRIPTS/test_gradcam.py

Set IMG_PATH below to the image you want to analyze.
"""
import os
import sys
import numpy as np
import tensorflow as tf
import matplotlib.pyplot as plt
import matplotlib.cm as cm

# Import shared model utilities
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from model_utils import load_model, CLASS_NAMES

# ============================================================
# ✅ PASTE THE PATH TO YOUR TEST IMAGE HERE
IMG_PATH = r'/Users/mj/Downloads/septoria_tom_seedlings1x1200.jpg'
# ============================================================


def make_gradcam_heatmap(model, img_array, target_class_idx=None):
    """
    Generate a Grad-CAM heatmap for the given image.
    
    Uses the last Conv2D layer in the model (after SpatialAttention)
    to produce the class activation map.
    """
    # Find the last Conv2D layer (the one before Reshape)
    last_conv_layer = None
    for layer in model.layers:
        if isinstance(layer, tf.keras.layers.Conv2D):
            last_conv_layer = layer
    
    if last_conv_layer is None:
        print("❌ No Conv2D layer found in model.")
        return None
    
    print(f"   📍 Using layer: '{last_conv_layer.name}' for Grad-CAM")
    
    # Build a model that outputs both the conv layer output and the final predictions
    grad_model = tf.keras.Model(
        inputs=model.input,
        outputs=[last_conv_layer.output, model.output]
    )
    
    # Compute gradients
    with tf.GradientTape() as tape:
        conv_outputs, predictions = grad_model(img_array, training=False)
        
        if target_class_idx is None:
            target_class_idx = tf.argmax(predictions[0])
        
        target_score = predictions[:, target_class_idx]
    
    # Gradient of the target class score w.r.t. the conv layer output
    grads = tape.gradient(target_score, conv_outputs)
    
    # Global average pooling of the gradients → channel importance weights
    pooled_grads = tf.reduce_mean(grads, axis=(0, 1, 2))
    
    # Weighted combination of feature maps
    conv_outputs = conv_outputs[0]
    heatmap = conv_outputs @ pooled_grads[..., tf.newaxis]
    heatmap = tf.squeeze(heatmap)
    
    # ReLU and normalize to [0, 1]
    heatmap = tf.maximum(heatmap, 0) / (tf.math.reduce_max(heatmap) + 1e-8)
    
    return heatmap.numpy()


def overlay_heatmap(img, heatmap, alpha=0.4):
    """Overlay heatmap on top of the original image."""
    # Resize heatmap to match image size
    heatmap_resized = np.uint8(255 * heatmap)
    
    # Use jet colormap
    jet = cm.get_cmap("jet")
    jet_colors = jet(np.arange(256))[:, :3]
    jet_heatmap = jet_colors[heatmap_resized]
    
    # Resize heatmap to image dimensions
    jet_heatmap = tf.image.resize(
        jet_heatmap[np.newaxis], (img.shape[0], img.shape[1])
    )[0].numpy()
    
    # Normalize original image to [0, 1]
    img_normalized = np.array(img, dtype=np.float32)
    if img_normalized.max() > 1.0:
        img_normalized = img_normalized / 255.0
    
    # Superimpose
    superimposed = jet_heatmap * alpha + img_normalized * (1 - alpha)
    superimposed = np.clip(superimposed, 0, 1)
    
    return superimposed


def run_gradcam(image_path):
    """Run Grad-CAM analysis on a single image."""
    print(f"\n🔍 Analyzing: {os.path.basename(image_path)}")
    
    # 1. Load Image (original size)
    img = tf.keras.utils.load_img(image_path)
    img_array = tf.keras.utils.img_to_array(img)
    
    # Smart Preprocessing: Center crop to square, then resize
    h, w, _ = img_array.shape
    min_dim = min(h, w)
    
    start_h = (h - min_dim) // 2
    start_w = (w - min_dim) // 2
    img_cropped = img_array[start_h:start_h+min_dim, start_w:start_w+min_dim, :]
    
    img_resized = tf.image.resize(img_cropped, (224, 224))
    img_array_batch = np.expand_dims(img_resized, axis=0)
    
    # Update image for display
    img = tf.keras.utils.array_to_img(img_resized)
    
    # 2. Get prediction
    preds = model.predict(img_array_batch, verbose=0)[0]
    pred_idx = np.argmax(preds)
    pred_label = CLASS_NAMES[pred_idx]
    confidence = preds[pred_idx] * 100
    
    print(f"   🏷️  Prediction: {pred_label} ({confidence:.1f}%)")
    
    # 3. Generate Grad-CAM heatmap
    print("   🔥 Generating Grad-CAM heatmap...")
    heatmap = make_gradcam_heatmap(model, img_array_batch, pred_idx)
    
    if heatmap is None:
        return
    
    # 4. Create overlay
    superimposed = overlay_heatmap(img_array, heatmap, alpha=0.4)
    
    # 5. Display results
    fig, axes = plt.subplots(1, 3, figsize=(15, 5))
    
    # Original image
    axes[0].imshow(img)
    axes[0].set_title("Original Image", fontsize=12, fontweight='bold')
    axes[0].axis('off')
    
    # Heatmap only
    axes[1].imshow(heatmap, cmap='jet')
    axes[1].set_title("Grad-CAM Heatmap", fontsize=12, fontweight='bold')
    axes[1].axis('off')
    
    # Overlay
    axes[2].imshow(superimposed)
    color = 'darkgreen' if confidence > 80 else 'darkorange'
    axes[2].set_title(f"Overlay: {pred_label} ({confidence:.1f}%)",
                      fontsize=12, fontweight='bold', color=color)
    axes[2].axis('off')
    
    plt.suptitle("TOMOLeafNet Grad-CAM Analysis", fontsize=14, fontweight='bold')
    plt.tight_layout()
    
    # Save the result
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    save_path = os.path.join(base_dir, 'RESULTS', 'GradCAM_Result.png')
    plt.savefig(save_path, dpi=150, bbox_inches='tight')
    print(f"   💾 Saved to: {save_path}")
    
    plt.show()
    
    # Print top-3 classes
    top_3 = np.argsort(preds)[-3:][::-1]
    print(f"\n📊 Top 3 predictions:")
    for rank, idx in enumerate(top_3, 1):
        print(f"   {rank}. {CLASS_NAMES[idx]}: {preds[idx]*100:.2f}%")


# --- MAIN ---
print("🌿 TOMOLeafNet Grad-CAM Visualizer")
model = load_model()
run_gradcam(IMG_PATH)
