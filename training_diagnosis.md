# TomoLeafNet v3 — Training Diagnosis & Improvement Plan

## 1. Graph Analysis

### Numerical Summary (from [training_history.json](file:///c:/Users/iamha/Development/TOMOLEAFNET-v1/RESULTS/training_history.json))

| Metric | Phase 1 (ep 1-10) | Phase 2 (ep 11-35) | Final |
|--------|-------------------|---------------------|-------|
| Train Loss | 0.70 → 0.20 | 0.73 → 0.19 | **0.185** |
| Val Loss | 0.65 → 0.51 | 0.72 → 0.36 | **0.358** |
| Train Acc | 73.1% → 92.9% | 78.4% → 93.7% | **93.7%** |
| Val Acc | 78.3% → 82.3% | 78.2% → 87.3% | **87.3%** |

### Diagnosed Issues

**A. Val loss >> Train loss (generalization gap of ~0.17)**
- Train loss settles at **0.185** while val loss stays at **0.358** — nearly **2× higher**
- This is classic **moderate overfitting**: the model memorizes training patterns that don't generalize

**B. High volatility in Phase 1 (epochs 1-10)**
- Val loss oscillates wildly: 0.65 → 0.54 → **0.87** → 0.40 → 0.34 → **0.91** → 0.38
- Root cause: **learning rate too high** for Adam default (`lr=0.001`) on a small dataset

**C. Sharp drop at fine-tune start (epoch 11)**
- Train loss jumps from 0.20 → **0.73** (a 3.7× spike)
- Train accuracy drops from 92.9% → **78.4%**
- Root cause: unfreezing 30 layers **abruptly** with `lr=1e-5` causes feature destruction before the optimizer adapts

**D. Val accuracy plateau at ~87%**
- Val accuracy climbs slowly in Phase 2 but flattens after epoch 30
- Despite 25 more epochs of fine-tuning, only gains **+5%** over Phase 1 ending val accuracy

---

## 2. Codebase Root Causes

### Architecture & Regularization

| Component | Current | Issue |
|-----------|---------|-------|
| Base model | MobileNetV3Small (no top) | Good — lightweight |
| Dropout | Single `Dropout(0.3)` before output | **Insufficient** — only 1 layer, applied after GlobalAvgPool |
| BatchNorm | Only inside MobileNetV3 (not in custom head) | Head layers lack normalization |
| Weight decay | **None** | No L2 regularization anywhere |
| Custom layers | SpatialAttention + TransformerBlock | Neither has dropout or regularization |

> [!WARNING]
> The TransformerBlock has **no dropout** in its attention or residual path, which is standard practice in ViT architectures to prevent overfitting.

### Learning Rate Strategy

```python
# Phase 1: lr=0.001 (Adam default) — TOO HIGH for small dataset
model.compile(optimizer='adam', ...)

# Phase 2: lr=0.00001 — abrupt 100× drop
model.compile(optimizer=optimizers.Adam(1e-5), ...)
```

**Problems:**
- Phase 1 `lr=0.001` creates the oscillating validation loss
- **No warmup schedule** — fine-tuning starts at full `1e-5` immediately
- **No cosine decay or reduce-on-plateau** — LR stays flat throughout

### Data Augmentation

```python
augment = tf.keras.Sequential([
    RandomFlip("horizontal_and_vertical"),   # ← vertical flip is unusual for leaves
    RandomRotation(0.3),                     # 0.3 = ±54° — very aggressive
    RandomZoom((-0.3, 0.0)),                 # up to 30% zoom-in only
    RandomTranslation(0.1, 0.1),
    RandomContrast(0.3),                     # ±30% contrast — aggressive
    RandomBrightness(0.3),                   # ±30% brightness — aggressive
    GaussianNoise(0.1),
])
```

**Problems:**
- **Vertical flip** is unusual — tomato leaves don't naturally appear upside-down, adds noise
- **0.3 rotation** (±54°) is very aggressive — leaf veins at extreme angles look unnatural
- Combined strong augmentation on only **~700 images/class** makes the training target too noisy
- No **cutout/erasing** augmentation which is effective for disease spot models

### Dataset Size

- **3,532 training images** across 5 classes (~700/class) is **small** for a hybrid CNN+Transformer
- Balanced distribution (good — no class imbalance issue)
- The model has **~2.3M parameters** — too many for this dataset without strong regularization

---

## 3. Improvement Recommendations

### Priority 1: Stabilize Training & Close the Gap

#### A. Add proper regularization in [train.py](file:///c:/Users/iamha/Development/TOMOLEAFNET-v1/SCRIPTS/train.py#L61-L72)

```diff
 x = SpatialAttention()(x)
 x = layers.Conv2D(128, 1)(x)
+x = layers.BatchNormalization()(x)            # normalize before reshape
 s = x.shape
 x = layers.Reshape((s[1] * s[2], s[3]))(x)
 x = TransformerBlock()(x)
 x = layers.GlobalAveragePooling1D()(x)
-x = layers.Dropout(0.3)(x)
+x = layers.Dropout(0.4)(x)                    # increase dropout
+x = layers.Dense(64, activation='relu',
+    kernel_regularizer=tf.keras.regularizers.l2(1e-4))(x)  # bottleneck with L2
+x = layers.Dropout(0.3)(x)
 out = layers.Dense(len(train_ds.class_names), activation='softmax')(x)
```

#### B. Add dropout inside TransformerBlock in [model_utils.py](file:///c:/Users/iamha/Development/TOMOLEAFNET-v1/SCRIPTS/model_utils.py#L45-L65)

```diff
 class TransformerBlock(layers.Layer):
     def __init__(self, **kwargs):
         super().__init__(**kwargs)
         self.norm = layers.LayerNormalization()
         self.mha = layers.MultiHeadAttention(num_heads=4, key_dim=128)
+        self.dropout = layers.Dropout(0.1)

     def call(self, x):
         skip = x
         x = self.norm(x)
         x = self.mha(x, x)
+        x = self.dropout(x)
         return x + skip
```

### Priority 2: Fix Learning Rate Strategy

#### C. Use a lower Phase 1 LR and warmup for Phase 2

```diff
 # Phase 1: Lower learning rate for stability
-model.compile(optimizer='adam', loss='categorical_crossentropy', metrics=['accuracy'])
+model.compile(
+    optimizer=optimizers.Adam(3e-4),  # 3x lower than default
+    loss='categorical_crossentropy', metrics=['accuracy']
+)

 # Phase 2: Cosine decay with warmup
-model.compile(optimizer=optimizers.Adam(1e-5), ...)
+total_steps = len(train_ds) * 25
+lr_schedule = tf.keras.optimizers.schedules.CosineDecay(
+    initial_learning_rate=5e-5,
+    decay_steps=total_steps,
+    alpha=1e-6  # minimum LR
+)
+model.compile(
+    optimizer=optimizers.Adam(lr_schedule),
+    loss='categorical_crossentropy', metrics=['accuracy']
+)
```

### Priority 3: Tone Down Augmentation

#### D. Reduce augmentation aggressiveness

```diff
 augment = tf.keras.Sequential([
-    layers.RandomFlip("horizontal_and_vertical"),
+    layers.RandomFlip("horizontal"),              # remove vertical flip
-    layers.RandomRotation(0.3),
+    layers.RandomRotation(0.15),                  # ±27° instead of ±54°
-    layers.RandomZoom((-0.3, 0.0)),
+    layers.RandomZoom((-0.15, 0.05)),             # gentler zoom range
     layers.RandomTranslation(0.1, 0.1),
-    layers.RandomContrast(0.3),
+    layers.RandomContrast(0.15),                  # halved
-    layers.RandomBrightness(0.3),
+    layers.RandomBrightness(0.15),                # halved
     layers.GaussianNoise(0.1),
 ])
```

### Priority 4: Add ReduceLROnPlateau Callback

#### E. Dynamic LR reduction when validation plateaus

```diff
 history2 = model.fit(train_ds, validation_data=val_ds, epochs=25, callbacks=[
     callbacks.EarlyStopping(patience=5, restore_best_weights=True),
     callbacks.ModelCheckpoint(SAVE_PATH, save_best_only=True),
+    callbacks.ReduceLROnPlateau(
+        monitor='val_loss', factor=0.5, patience=3, min_lr=1e-7, verbose=1
+    ),
 ])
```

---

## Expected Impact

| Change | Expected Improvement |
|--------|---------------------|
| TransformerBlock dropout + L2 regularization | Reduce val-train gap from ~6% → ~2-3% |
| Lower Phase 1 LR (3e-4) | Eliminate val loss oscillation in epochs 1-10 |
| Cosine decay + warmup for Phase 2 | Prevent sharp drop at epoch 11, smoother convergence |
| Gentler augmentation | Less noisy training signal, faster convergence |
| ReduceLROnPlateau | Push past 87% plateau by adapting LR when stuck |
| **Combined** | **Target: 90-93% val accuracy** |

---

## How to Apply

Two approaches:

1. **I can apply all changes automatically** to [train.py](file:///c:/Users/iamha/Development/TOMOLEAFNET-v1/SCRIPTS/train.py) and [model_utils.py](file:///c:/Users/iamha/Development/TOMOLEAFNET-v1/SCRIPTS/model_utils.py) and you retrain
2. **Apply incrementally** — start with Priority 1 (regularization), retrain, measure, then add Priorities 2-4

> [!IMPORTANT]
> After applying changes, you must retrain with `python SCRIPTS/train.py`. The existing model will be overwritten.
