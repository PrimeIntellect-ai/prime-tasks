#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest pandas numpy scikit-learn pytesseract Pillow

    mkdir -p /app/data

    cat << 'EOF' > /tmp/gen_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
df = pd.DataFrame({
    'id': range(1, 1001),
    'feature_A': np.random.uniform(-10, 10, 1000),
    'feature_B': np.random.uniform(0, 100, 1000),
    'feature_C': np.random.normal(5, 2, 1000)
})
df.to_csv('/app/data/batch_001.csv', index=False)
EOF
    python3 /tmp/gen_data.py

    convert -size 800x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 50,100 'MODEL EQUATION: score = 3.14 * feature_A - 1.618 * feature_B + 2.718 * feature_C + 42.0'" /app/legacy_model_spec.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
