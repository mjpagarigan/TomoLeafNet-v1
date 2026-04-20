# TomoLeafNet v4 — Training Guide (Anaconda + Windows)

Step-by-step guide to retrain the TomoLeafNet v4 model from scratch on your
Lenovo IdeaPad (RTX 3050 4GB, 16GB RAM, CUDA 12.6).

---

## 1. Install Anaconda

1. Download Anaconda from https://www.anaconda.com/download
2. Run the installer. Check **"Add Anaconda to my PATH"** when prompted.
3. After installation, open **Anaconda Prompt** (search for it in the Start menu).
4. Verify:
   ```
   conda --version
   ```

---

## 2. Create the Virtual Environment

Open **Anaconda Prompt** and run:

```bash
# Create a new environment named "tomoleafnet" with Python 3.10
conda create -n tomoleafnet python=3.10 -y

# Activate it
conda activate tomoleafnet
```

You should see `(tomoleafnet)` at the start of your prompt.

---

## 3. Install Dependencies

Your RTX 3050 has CUDA 12.6 drivers. TensorFlow 2.16+ supports CUDA 12 natively.

```bash
# Install TensorFlow with GPU support (CUDA 12)
pip install tensorflow[and-cuda]

# Install remaining dependencies
pip install scikit-learn matplotlib seaborn
```

### Verify GPU is detected

```bash
python -c "import tensorflow as tf; print('GPUs:', tf.config.list_physical_devices('GPU'))"
```

Expected output:
```
GPUs: [PhysicalDevice(name='/physical_device:GPU:0', device_type='GPU')]
```

If you see an empty list `[]`, see Troubleshooting at the bottom.

---

## 4. Navigate to the Project

```bash
cd C:\Users\iamha\OneDrive\Documents\GitHub\TomoLeafNet-v1
```

---

## 5. Prepare the Dataset

### 5a. Verify raw data exists

Make sure these folders have images:
```
DATA-RAW/field/Early_Blight/
DATA-RAW/field/Healthy/
DATA-RAW/field/Leaf_Miner/
DATA-RAW/field/Leaf_Mold/
DATA-RAW/field/Not_Tomato/
DATA-RAW/public/Early_Blight/
DATA-RAW/public/Healthy/
DATA-RAW/public/Leaf_Miner/
DATA-RAW/public/Leaf_Mold/
DATA-RAW/public/Not_Tomato/
```

Quick check:
```bash
python -c "
import os
for split in ['field', 'public']:
    base = f'DATA-RAW/{split}'
    for cls in os.listdir(base):
        p = os.path.join(base, cls)
        if os.path.isdir(p):
            n = len([f for f in os.listdir(p) if f.lower().endswith(('.jpg','.jpeg','.png'))])
            print(f'  {split}/{cls}: {n} images')
"
```

### 5b. Run the augmentation + split script

```bash
python 0_augment_field_dataset.py
```

This will:
- Augment each class to 1,000 images
- Split into train/val/test (70/15/15)
- Val and test contain **only real images** (no synthetics)
- Output goes to `DATA-SPLIT/target_field/`

Expected output:
```
  Early_Blight: 377 real + 623 synthetic = 1000 total
  Healthy:      902 real +  98 synthetic = 1000 total
  Leaf_Miner:   560 real + 440 synthetic = 1000 total
  Leaf_Mold:    386 real + 614 synthetic = 1000 total
  Not_Tomato:   500 real + 500 synthetic = 1000 total

  Split complete: train=3500 | val=750 | test=750
```

---

## 6. Train Phase 1 (Warm-Up on Public Dataset)

```bash
python 1_train_phase1.py
```

**What it does:**
- Splits the public 5-class dataset (80/20 train/val)
- Builds MobileNetV3Large with frozen backbone
- Trains for 15 epochs on public data
- Saves best model to `MODEL/phase1_base.keras`

**Expected time:** ~5-8 minutes on RTX 3050

**Expected result:** Val accuracy ~92-96%

### RTX 3050 4GB memory tip

If you get an OOM (out-of-memory) error, add this at the top of the script
(before any TensorFlow imports):

```python
import os
os.environ['TF_GPU_ALLOCATOR'] = 'cuda_malloc_async'
```

Or reduce batch size by editing the script:
```python
BATCH_SIZE = 16  # was 32
```

---

## 7. Train Phase 2 (Fine-Tune on Field Dataset)

```bash
python 2_train_phase2.py
```

**What it does:**
- Loads the Phase 1 warm-up model
- 3-stage progressive unfreeze on field data:
  - Stage 1 (20 epochs): Unfreeze last 30 layers, LR=5e-5
  - Stage 2 (20 epochs): Unfreeze last 60 layers, LR=3e-5
  - Stage 3 (up to 45 epochs): Full model, LR=1e-5, early stopping
- Augmentations: horizontal flip, rotation, zoom, translation, contrast,
  brightness, Gaussian noise, motion blur, random shadow, random erasing
- Mixup (alpha=0.1) + class weights
- Saves best model to `MODEL/tomoleafnet_v4_final.keras`
- Exports TFLite to `MODEL/tomoleafnet_v4.tflite`
- Saves training curves to `RESULTS/Phase2_Curves.png`
- Saves epoch metrics to `RESULTS/Phase2_History.csv`

**Expected time:** ~45-90 minutes on RTX 3050 (depends on early stopping)

**Expected result:** Val accuracy ~90-95%

### If training crashes or you need to resume

The best model is checkpointed every time val_accuracy improves. If training
crashes mid-stage, the best weights so far are already saved in
`MODEL/tomoleafnet_v4_final.keras`.

---

## 8. Evaluate on Unseen Test Set

```bash
python 3_evaluate_metrics.py
```

**What it does:**
- Loads the final Keras model
- Evaluates on the held-out test set (real images only, never seen during training)
- Prints classification report + per-class accuracy
- Saves confusion matrix to `RESULTS/Confusion_Matrix.png`
- Compares Keras vs TFLite accuracy (flags >2% divergence)

**Expected output:**
```
  CLASSIFICATION REPORT
  ============================================================
                precision    recall  f1-score   support
   Early_Blight     0.92      0.89      0.90       150
        Healthy     0.95      0.97      0.96       150
     Leaf_Miner     0.91      0.93      0.92       150
      Leaf_Mold     0.90      0.88      0.89       150
     Not_Tomato     0.97      0.96      0.97       150

       accuracy                         0.93       750
  ============================================================

  KERAS vs TFLITE COMPARISON
  ============================================================
    Keras accuracy:     93.xx%
    TFLite accuracy:    92.xx%
    Accuracy delta:     0.xx%
    [OK] TFLite accuracy is within acceptable range.
```

---

## 9. Deploy to Mobile App

### 9a. Copy the TFLite model to the Flutter assets

```bash
copy MODEL\tomoleafnet_v4.tflite MOBILE_APP\assets\tomoleafnet_v4.tflite
```

### 9b. Verify labels match

Make sure `MOBILE_APP/assets/labels.txt` contains exactly:
```
Early_Blight
Healthy
Leaf_Miner
Leaf_Mold
Not_Tomato
```

### 9c. Build and test

```bash
cd MOBILE_APP
flutter pub get
flutter run
```

---

## 10. Full Pipeline — One-Shot Commands

If you want to run everything from scratch in one go:

```bash
conda activate tomoleafnet

cd C:\Users\iamha\OneDrive\Documents\GitHub\TomoLeafNet-v1

python 0_augment_field_dataset.py
python 1_train_phase1.py
python 2_train_phase2.py
python 3_evaluate_metrics.py

copy MODEL\tomoleafnet_v4.tflite MOBILE_APP\assets\tomoleafnet_v4.tflite
```

---

## Troubleshooting

### "No GPU detected" / empty GPU list

1. Make sure NVIDIA drivers are up to date (you have 560.76 / CUDA 12.6 — this is fine)
2. Try installing CUDA toolkit via conda as a fallback:
   ```bash
   conda install -c conda-forge cudatoolkit=12.4 cudnn=9.* -y
   pip install tensorflow[and-cuda]
   ```
3. Restart Anaconda Prompt and re-check

### OOM (Out of Memory) on RTX 3050 4GB

Your GPU has 4GB VRAM. If training crashes with OOM:

1. **Reduce batch size** — edit `BATCH_SIZE = 16` (or even `8`) in the training script
2. **Enable memory growth** — add to the top of the script:
   ```python
   import tensorflow as tf
   gpus = tf.config.list_physical_devices('GPU')
   if gpus:
       tf.config.experimental.set_memory_growth(gpus[0], True)
   ```
3. **Limit GPU memory** — restrict TF to 3.5GB:
   ```python
   import tensorflow as tf
   gpus = tf.config.list_physical_devices('GPU')
   if gpus:
       tf.config.set_logical_device_configuration(
           gpus[0],
           [tf.config.LogicalDeviceConfiguration(memory_limit=3584)]
       )
   ```

### "DLL not found" / cuDNN errors

```bash
# Make sure the conda env has the CUDA libraries
conda install -c conda-forge cudatoolkit=12.4 cudnn=9.* -y
```

### Training is very slow / using CPU only

Check if TF is using the GPU during training:
```bash
python -c "
import tensorflow as tf
print('Built with CUDA:', tf.test.is_built_with_cuda())
print('GPU available:', tf.config.list_physical_devices('GPU'))
print('TF version:', tf.__version__)
"
```

If `GPU available` is empty, TensorFlow can't find CUDA libraries. Reinstall:
```bash
pip uninstall tensorflow -y
pip install tensorflow[and-cuda]
```

### Anaconda Prompt vs regular terminal

Always use **Anaconda Prompt** (not PowerShell or Git Bash) to ensure the
conda environment paths are set correctly. If you prefer using a regular
terminal, run `conda init bash` or `conda init powershell` first.

---

## Environment Summary

| Component | Version |
|-----------|---------|
| OS | Windows 11 Home |
| GPU | NVIDIA RTX 3050 Laptop (4GB) |
| CUDA Driver | 12.6 |
| RAM | 16GB |
| Python | 3.10 (in conda env) |
| TensorFlow | 2.16+ (with CUDA 12 support) |
| Model | MobileNetV3Large |
| Input size | 224 x 224 x 3 |
| Output | 5 classes (softmax) |
