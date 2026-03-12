"""
Convert Keras (.keras or .h5) model to TFLite format.
Ensures custom layers (SpatialAttention, TransformerBlock) are handled correctly.
"""
import os
import sys
import tensorflow as tf

# Import shared model utilities
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from model_utils import load_model

# Paths
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TFLITE_PATH = os.path.join(BASE_DIR, 'MODEL', 'tomoleafnet_v3.tflite')

def convert_to_tflite():
    print("⏳ Loading Keras model...")
    # Load the full model (training model)
    full_model = load_model()
    
    print("✂️  Stripping Augmentation layers for Inference...")
    # The training model has: Input -> Augmentation -> MobileNetV3 -> ...
    # We want: Input -> MobileNetV3 -> ...
    # We reconstruct the model graph starting from the layer AFTER augmentation.
    
    # Check if layer 1 is indeed the augmentation model
    if isinstance(full_model.layers[1], tf.keras.Sequential):
         print(f"   Found augmentation layer: {full_model.layers[1].name}")
    
    # Create new input
    new_input = tf.keras.Input(shape=(224, 224, 3), name='inference_input')
    x = new_input
    
    # Re-build the graph, skipping the augmentation layer (index 1)
    # We assume layer 0 is Input, layer 1 is Augment.
    # We iterate from layer 2 onwards.
    for layer in full_model.layers[2:]:
        x = layer(x)
        
    inference_model = tf.keras.Model(inputs=new_input, outputs=x, name='tomoleafnet_v3_inference')
    
    print("📱 Converting to TFLite (via SavedModel)...")
    
    # Use the inference model for conversion
    model = inference_model
    
    # Keras 3 fix: Export to SavedModel first
    # This bypasses the direct Keras->TFLite path which is buggy in TF 2.16 + Keras 3
    SAVED_MODEL_DIR = os.path.join(BASE_DIR, 'MODEL', 'temp_saved_model')
    try:
        model.export(SAVED_MODEL_DIR) # Keras 3 native export
    except AttributeError:
        # Fallback for older Keras 3 versions or if export is missing
        tf.saved_model.save(model, SAVED_MODEL_DIR)
        
    # Convert from SavedModel
    converter = tf.lite.TFLiteConverter.from_saved_model(SAVED_MODEL_DIR)
    
    # Optimize
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    
    tflite_model = converter.convert()
    
    print(f"💾 Saving to: {TFLITE_PATH}")
    with open(TFLITE_PATH, 'wb') as f:
        f.write(tflite_model)
        
    # Cleanup
    import shutil
    try:
        shutil.rmtree(SAVED_MODEL_DIR)
    except:
        pass
        
    print(f"✅ TFLite conversion complete!")
    print(f"   Size: {os.path.getsize(TFLITE_PATH) / 1024 / 1024:.2f} MB")

if __name__ == "__main__":
    convert_to_tflite()
