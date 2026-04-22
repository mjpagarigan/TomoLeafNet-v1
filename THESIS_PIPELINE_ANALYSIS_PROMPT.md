# Thesis Pipeline Analysis Prompt

```md
Analyze the complete TomoLeafNet data and inference pipeline in this repository and write a thesis-ready technical explanation in Markdown.

Your goal is to explain, in a clear and academically useful way, how the system works from raw image acquisition to final disease prediction on the mobile app, including the training pipeline, evaluation pipeline, model conversion pipeline, and explainability pipeline.

Scope and priorities:

1. Start with a high-level system overview.
   Explain the full end-to-end flow from:
   - leaf capture in the mobile app,
   - tomato-leaf detection or rejection logic if present,
   - image preprocessing,
   - disease classification,
   - result rendering in the app,
   - model training in Keras,
   - export to TFLite,
   - and heatmap / Grad-CAM or CAM-style explainability.

2. Trace the dataset pipeline in detail.
   Explain:
   - where the raw datasets come from,
   - the role of the `Not_Tomato` rejection class,
   - how `DATA-RAW/field` and `DATA-RAW/public` are used,
   - how the field dataset is balanced to 1,000 images per class,
   - which augmentations are applied,
   - why only the training split receives synthetic images,
   - and how the final train/validation/test splits are formed.

3. Explain the two-phase training pipeline step by step.
   Cover:
   - `0_augment_field_dataset.py`
   - `1_train_phase1.py`
   - `2_train_phase2.py`
   - `3_evaluate_metrics.py`
   - `4_export_cam_model.py` if relevant

   For each script, explain:
   - its purpose,
   - its inputs and outputs,
   - its role in the larger pipeline,
   - and the important implementation details that affect model performance.

4. Analyze the model architecture and training strategy.
   Include:
   - why MobileNetV3Large is used,
   - the classifier head design,
   - frozen-base warm-up in Phase 1,
   - progressive unfreezing in Phase 2,
   - BatchNorm freezing behavior,
   - Mixup usage,
   - class weighting,
   - dropout,
   - Gaussian noise,
   - cosine learning-rate decay with warmup,
   - checkpointing,
   - early stopping,
   - CSV logging,
   - and any other important regularization or optimization choices.

5. Extract and summarize all important hyperparameters in a clean table.
   Include at minimum:
   - image size,
   - batch size,
   - seed,
   - epochs per phase and per stage,
   - optimizer,
   - loss function,
   - learning rates,
   - warmup configuration,
   - Mixup alpha,
   - augmentation ranges,
   - class labels,
   - confidence thresholds,
   - and any TFLite or mobile inference thresholds used by the app.

6. Explain preprocessing very carefully.
   Clarify:
   - center-crop behavior,
   - resize behavior,
   - normalization behavior,
   - why MobileNetV3 preprocessing is intentionally kept outside the Keras model graph,
   - how this affects TFLite conversion,
   - and how preprocessing is reproduced in Flutter so training and deployment stay aligned.

7. Explain the Keras-to-TFLite deployment path.
   Discuss:
   - how the best Keras model is saved,
   - when `.keras` versus `.h5` fallback is used,
   - how SavedModel export is used before TFLite conversion,
   - what optimization is applied during conversion,
   - what risks exist during conversion,
   - and how `3_evaluate_metrics.py` compares Keras and TFLite predictions to detect preprocessing or quantization mismatch.

8. Explain the mobile inference pipeline in the Flutter app.
   Describe:
   - camera capture flow,
   - any separate tomato-leaf detector model before disease classification,
   - temporal smoothing or threshold logic if present,
   - how the image is preprocessed for TFLite,
   - how top-1 and top-2 predictions are used,
   - ambiguity handling,
   - rejection handling for `Not_Tomato`,
   - and how results are saved or displayed.

9. Explain the Grad-CAM / CAM / heatmap pipeline.
   If the repository uses a true Grad-CAM implementation, explain it.
   If it instead uses CAM-style projection or another explainability method, state that clearly and do not mislabel it.
   Explain:
   - how the heatmap model is exported,
   - what the extra output tensor represents,
   - how the 7x7 class activation maps are generated,
   - how they are normalized and upscaled,
   - how they are overlaid in the mobile app,
   - and the practical purpose of this explainability feature.

10. Reconcile the repository versions carefully.
    This repository contains multiple script versions and some legacy files.
    Distinguish:
    - the main pipeline that should be considered the primary thesis pipeline,
    - older or experimental scripts that appear to be legacy or comparison artifacts,
    - and current app behavior that may have evolved beyond the older AGENTS description.
    If there are inconsistencies between documentation and code, explicitly point them out.

11. Provide a critical analysis section.
    Do not only describe what the code does.
    Also explain:
    - why each design choice is reasonable,
    - what tradeoffs it introduces,
    - what risks or limitations exist,
    - and what parts of the pipeline are most important to discuss in a thesis defense.

12. End with a concise conclusion.
    Summarize the full pipeline from image capture to on-device disease detection in a way that could be reused in a thesis chapter.

Output requirements:

- Write the response as a polished Markdown document.
- Use clear section headings.
- Use tables where useful, especially for hyperparameters and pipeline stages.
- Use precise technical language, but keep the explanation readable for a thesis panel.
- Ground every explanation in the repository’s actual code and structure.
- Reference relevant files and functions by name throughout the analysis.
- Do not invent steps that are not present in the code.
- If a detail is ambiguous or differs across versions, explicitly say so.
- Prefer a structured, narrative analysis over bullet-only notes.
- Include one end-to-end pipeline diagram in Mermaid if possible.

Important interpretation rule:

- Treat the repository code as the primary source of truth.
- Use documentation files only as supporting context.
- If the mobile app currently uses a different inference flow than the older training description, explain both and clarify which one is current.
```
