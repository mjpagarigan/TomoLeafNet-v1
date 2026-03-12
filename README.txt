TOMOLEAFNET: TOMATO LEAF DISEASE DETECTION

This project utilizes a Deep Learning model (TomoLeafNet v1) to classify tomato leaf diseases into 5 distinct categories. The system evaluates model performance using a confusion matrix and classification report to ensure high accuracy in real-world scenarios.

PROJECT STRUCTURE

TOMOLEAFNET-v1/
MODEL/
tomoleafnet_v3_hybrid.h5 (The trained Deep Learning model)
DATA-LABEL/ (Dataset for validation/testing)
Bacterial_Spot/
Early_Blight/
Healthy/
Late_Blight/
Septoria/
DATA-SPLIT/ (Preprocessed dataset split: 70% train / 15% val / 15% test)
train/
val/
test/
evaluate_model.py (Script to generate Confusion Matrix & Metrics)
requirements.txt (Python dependencies)
README.txt (Project documentation)

TECHNOLOGIES USED

TensorFlow/Keras: For loading the pre-trained .h5 model and making predictions.
NumPy: For array manipulation and handling image data.
Matplotlib & Seaborn: For visualizing the Confusion Matrix heatmaps.
Scikit-Learn: For calculating Precision, Recall, F1-Score, and Accuracy.

HOW IT WORKS (STEP-BY-STEP PROCESSING)

The evaluation script (evaluate_model.py) processes the data in the following pipeline:

1. Model Loading
The script loads the pre-trained CNN model tomoleafnet_v3_hybrid.h5. This model has already learned to recognize features like spots, yellowing, and lesions on tomato leaves.

2. Data Traversal
The script loops through the 5 specific class folders in DATA-LABEL.
It identifies images (.jpg, .png, .jpeg).
It limits testing to 1,000 images per class to ensure a balanced evaluation.

3. Image Preprocessing
Before the model sees an image, it is transformed to match the training conditions:
Resizing: The image is resized to 224x224 pixels.
Array Conversion: The image is converted into a NumPy array.
Batch Expansion: A dimension is added to create a batch of size 1.

4. Prediction
The model predicts the probability for all 5 classes.
The system selects the class with the highest probability as the Predicted Label.
This is compared against the True Label (the folder name).

5. Metric Calculation & Visualization
Once all images are processed, the system generates:
Classification Report: A table showing Precision, Recall, and F1-Score for each disease.
Confusion Matrix: A heatmap showing where the model gets confused.

HOW TO RUN

Step 1: Install Dependencies
Open your terminal or command prompt and install the required libraries:
pip install -r requirements.txt

Step 2: Verify Paths
Open evaluate_model.py and ensure your paths match your local directory.

Step 3: Execute the Script
Run the evaluation script:
python evaluate_model.py

Step 4: Analyze Results
Check the terminal for the Accuracy score and F1-scores.
A Confusion Matrix heatmap will appear. Save this image for your documentation.