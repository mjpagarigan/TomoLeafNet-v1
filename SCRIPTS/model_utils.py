"""
Shared model utilities for TOMOLeafNet.
Contains the custom layer definitions needed to load the trained model.
"""
import os
import tensorflow as tf
from tensorflow.keras import layers

# --- PROJECT PATHS ---
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL_PATH_KERAS = os.path.join(BASE_DIR, 'MODEL', 'tomoleafnet_v3_hybrid.keras')
MODEL_PATH_H5 = os.path.join(BASE_DIR, 'MODEL', 'tomoleafnet_v3_hybrid.h5')
# Prefer .keras format (Keras 3 native), fall back to .h5
MODEL_PATH = MODEL_PATH_KERAS if os.path.exists(MODEL_PATH_KERAS) else MODEL_PATH_H5
TFLITE_PATH = os.path.join(BASE_DIR, 'MODEL', 'tomoleafnet_v3.tflite')
DATA_LABEL_DIR = os.path.join(BASE_DIR, 'DATA-LABEL')
DATA_SPLIT_DIR = os.path.join(BASE_DIR, 'DATA-SPLIT')

# --- CLASS NAMES (alphabetical, matching model output order) ---
CLASS_NAMES = [
    "Bacterial_Spot", "Early_Blight",
    "Healthy", "Late_Blight", "Septoria"
]

# --- CUSTOM LAYERS (required for model loading) ---

class SpatialAttention(layers.Layer):
    """CBAM-style spatial attention to help Grad-CAM highlight leaf spots."""
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.conv = layers.Conv2D(1, (7, 7), padding='same', activation='sigmoid')
    
    def build(self, input_shape):
        self.conv.build(list(input_shape[:-1]) + [2])
        self.built = True
    
    def call(self, x):
        avg_p = tf.reduce_mean(x, axis=-1, keepdims=True)
        max_p = tf.reduce_max(x, axis=-1, keepdims=True)
        c = tf.concat([avg_p, max_p], axis=-1)
        att = self.conv(c)
        return x * att

class TransformerBlock(layers.Layer):
    """ViT-style self-attention block for global leaf structure understanding."""
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.norm = layers.LayerNormalization()
        self.mha = layers.MultiHeadAttention(num_heads=4, key_dim=128)
        self.drop = layers.Dropout(0.1)
    
    def build(self, input_shape):
        self.norm.build(input_shape)
        # Keras 2 MHA uses _build_from_signature instead of build(shape, shape)
        self.mha._build_from_signature(
            query=tf.keras.backend.placeholder(shape=input_shape),
            value=tf.keras.backend.placeholder(shape=input_shape),
        )
        self.drop.build(input_shape)
        self.built = True
    
    def call(self, x, training=None):
        skip = x
        x = self.norm(x)
        x = self.mha(x, x)
        x = self.drop(x, training=training)
        return x + skip

# --- MODEL LOADING ---

CUSTOM_OBJECTS = {
    'SpatialAttention': SpatialAttention,
    'TransformerBlock': TransformerBlock,
}

def load_model(model_path=None):
    """Load the TOMOLeafNet model with custom layers registered."""
    path = model_path or MODEL_PATH
    print(f"⏳ Loading model from: {path}")
    model = tf.keras.models.load_model(path, custom_objects=CUSTOM_OBJECTS)
    print("✅ Model loaded successfully.")
    return model
