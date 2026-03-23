# TomoLeafNet v3 — Running Python Scripts Tutorial

This guide covers how to set up the Python environment and run the testing/evaluation scripts on Windows.

---

## Prerequisites

- **Python 3.9 or 3.10** installed (TensorFlow 2.10.0 requires Python ≤ 3.10)
- All commands below should be run from the **project root** folder:
  ```
  C:\Users\iamha\OneDrive\Documents\GitHub\TomoLeafNet-v1
  ```

> **Check your Python version first:**
> ```bash
> python --version
> ```
> If you don't have Python, download **Python 3.10.x** from https://www.python.org/downloads/
> During install, check **"Add Python to PATH"**.

---

## Step 1: Create and Activate Virtual Environment

### Create the virtual environment (one time only)

```bash
python -m venv venv
```

### Activate it

```bash
venv\Scripts\activate
```

You should see `(venv)` at the beginning of your terminal prompt. This means the virtual environment is active.

> **Every time** you open a new terminal, you need to activate the venv again with the command above before running any scripts.

---

## Step 2: Install Dependencies

With the virtual environment **activated**, run:

```bash
pip install tensorflow==2.10.0 numpy matplotlib seaborn scikit-learn
```

This installs all required packages:
- `tensorflow` — model loading and inference
- `numpy` — array operations
- `matplotlib` — plotting and image display
- `seaborn` — confusion matrix heatmap
- `scikit-learn` — classification report and metrics

---

## Step 3: Test a Single Image (`test_image.py`)

This script predicts the disease class of a single leaf image.

### 3a. Edit the image path

Open `SCRIPTS\test_image.py` and change the `IMG_PATH` variable to point to your test image:

```python
IMG_PATH = r'C:\path\to\your\leaf_image.jpg'
```

For example:
```python
IMG_PATH = r'C:\Users\iamha\Downloads\test_leaf.jpg'
```

### 3b. Run the script

```bash
python SCRIPTS\test_image.py
```

### Expected output

```
⏳ Loading model from: ...\MODEL\tomoleafnet_v3_hybrid.keras
✅ Model loaded successfully.

RESULT: Early_Blight
CONFIDENCE: 94.32%
```

A matplotlib window will pop up showing the image with the prediction.

---

## Step 4: Generate Confusion Matrix & Classification Report (`results.py`)

This script runs the model on **all images** in `DATA-LABEL/` and generates:
- A full classification report (precision, recall, F1-score per class)
- A confusion matrix saved as `RESULTS\ConfusionMatrix.png`

### Run the script

```bash
python RESULTS\results.py
```

### Expected output

```
🚀 Running 5-class evaluation on DATA-LABEL folders...
   📁 Bacterial_Spot: testing 1000 images...
   📁 Early_Blight: testing 1000 images...
   📁 Healthy: testing 1000 images...
   📁 Late_Blight: testing 1000 images...
   📁 Septoria: testing 1000 images...

======================================================================
                      CLASSIFICATION REPORT
======================================================================
                precision    recall  f1-score   support
  Bacterial_Spot       0.95      0.93      0.94       ...
    Early_Blight       0.92      0.94      0.93       ...
         Healthy       0.98      0.97      0.98       ...
      Late_Blight      0.91      0.90      0.91       ...
        Septoria       0.93      0.95      0.94       ...
======================================================================

✅ Confusion matrix saved to: ...\RESULTS\ConfusionMatrix.png
```

> **Note:** This takes a while since it processes up to 1000 images per class. Be patient.

The confusion matrix image is saved at:
```
RESULTS\ConfusionMatrix.png
```

---

## Step 5: Grad-CAM Visualization (`test_gradcam.py`)

This generates a heatmap showing which parts of the leaf the model focused on.

### 5a. Edit the image path

Open `SCRIPTS\test_gradcam.py` and change the `IMG_PATH` variable:

```python
IMG_PATH = r'C:\path\to\your\leaf_image.jpg'
```

### 5b. Run the script

```bash
python SCRIPTS\test_gradcam.py
```

### Expected output

```
🌿 TOMOLeafNet Grad-CAM Visualizer
⏳ Loading model from: ...\MODEL\tomoleafnet_v3_hybrid.keras
✅ Model loaded successfully.

🔍 Analyzing: leaf_image.jpg
   🏷️  Prediction: Early_Blight (94.1%)
   🔥 Generating Grad-CAM heatmap...
   📍 Using layer: 'conv2d' for Grad-CAM
   💾 Saved to: ...\RESULTS\GradCAM_Result.png

📊 Top 3 predictions:
   1. Early_Blight: 94.12%
   2. Late_Blight: 3.45%
   3. Septoria: 1.22%
```

The visualization is saved at:
```
RESULTS\GradCAM_Result.png
```

---

## Quick Reference — Copy-Paste Commands

```bash
# -- First time setup --
python -m venv venv
venv\Scripts\activate
pip install tensorflow==2.10.0 numpy matplotlib seaborn scikit-learn

# -- Every time you open a new terminal --
venv\Scripts\activate

# -- Test single image (edit IMG_PATH in the file first) --
python SCRIPTS\test_image.py

# -- Generate confusion matrix + classification report --
python RESULTS\results.py

# -- Grad-CAM heatmap (edit IMG_PATH in the file first) --
python SCRIPTS\test_gradcam.py
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `python` not recognized | Install Python 3.10 and check "Add to PATH" during install. Or try `python3` instead. |
| `No module named tensorflow` | Make sure venv is activated (`venv\Scripts\activate`) and you ran `pip install`. |
| `ModuleNotFoundError: model_utils` | Run the command from the **project root** (`TomoLeafNet-v1`), not from inside `SCRIPTS/`. |
| Model loading error | Verify `MODEL\tomoleafnet_v3_hybrid.keras` exists. |
| `DATA-LABEL` folder empty | You need the dataset images in `DATA-LABEL\{class_name}\` folders for `results.py`. |
| Matplotlib window doesn't show | This is normal on some setups. The images are still saved to `RESULTS\`. |
