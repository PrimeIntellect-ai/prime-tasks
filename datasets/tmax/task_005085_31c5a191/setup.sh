#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pandas Pillow

    mkdir -p /app/data /app/hidden /home/user

    # Generate image using Python and Pillow to avoid ImageMagick policy/font issues
    cat << 'EOF' > /app/make_img.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color='white')
d = ImageDraw.Draw(img)
d.text((20, 50), "Threshold: value > 85.0", fill='black')
img.save('/app/rules.png')
EOF
    python3 /app/make_img.py
    rm /app/make_img.py

    # Generate CSV data
    cat << 'EOF' > /app/data/metrics.csv
date,ServerA,ServerB,ServerC
2023-01-01,12.5,45.2,88.1
2023-01-02,15.1,"42.1
",81.2
2023-01-03,11.2,44.4,90.5
2023-01-04,"99.9
",45.5,12.1
2023-01-05,14.4,46.1,15.2
EOF

    # Generate GT
    cat << 'EOF' > /app/hidden/anomalies_gt.csv
date,server_name,value
2023-01-01,ServerC,88.1
2023-01-03,ServerC,90.5
2023-01-04,ServerA,99.9
EOF

    # Evaluation script
    cat << 'EOF' > /app/hidden/eval.py
import pandas as pd
import sys

try:
    df_pred = pd.read_csv('/home/user/anomalies.csv')
    df_gt = pd.read_csv('/app/hidden/anomalies_gt.csv')

    merged = pd.merge(df_pred, df_gt, how='outer', indicator=True)
    tp = len(merged[merged['_merge'] == 'both'])
    fp = len(merged[merged['_merge'] == 'left_only'])
    fn = len(merged[merged['_merge'] == 'right_only'])

    precision = tp / (tp + fp) if (tp + fp) > 0 else 0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0
    f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0

    print(f1)
except Exception as e:
    print(0.0)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
