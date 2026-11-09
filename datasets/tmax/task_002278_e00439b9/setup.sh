#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest pandas scikit-learn numpy flask fastapi uvicorn pytesseract scipy

    mkdir -p /app

    # Generate the image
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 18 -fill black \
        -draw "text 10,30 'EXPERIMENT RUN RECORD' text 10,60 'ID: EXP-9942-X' text 10,90 'SEED: 1042' text 10,120 'ALPHA: 0.05' text 10,150 'BASELINE_ACC: 0.65'" \
        /app/experiment_summary.png

    # Generate the dataset
    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
from sklearn.datasets import make_classification
import numpy as np

X, y = make_classification(n_samples=500, n_features=5, random_state=42)
df = pd.DataFrame(X, columns=[f'feature_{i}' for i in range(5)])
df['target'] = y

# Add noise for schema enforcement
df.loc[10, 'feature_1'] = np.nan
df.loc[20, 'target'] = 2

df.to_csv('/app/dataset.csv', index=False)
EOF
    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
