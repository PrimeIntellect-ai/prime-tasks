#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
pip3 install pytest pytesseract pandas scipy Pillow

mkdir -p /app

# Generate cleaning_parameters.png
cat << 'EOF' > /app/generate_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color='white')
d = ImageDraw.Draw(img)
text = "Statistical parameters:\nAlpha: 0.05\nZ-score Threshold: 2.5\nMin Token Frequency: 3"
d.text((10,10), text, fill='black')
img.save('/app/cleaning_parameters.png')
EOF
python3 /app/generate_image.py

# Write oracle_pipeline.py
cat << 'EOF' > /app/oracle_pipeline.py
import sys
import pandas as pd
import numpy as np
from scipy import stats
from collections import Counter

def main():
    if len(sys.argv) != 3:
        sys.exit(1)
    in_csv = sys.argv[1]
    out_json = sys.argv[2]

    df = pd.read_csv(in_csv)

    # 2. Z-score filter
    mean = df['numeric_val'].mean()
    std = df['numeric_val'].std(ddof=0)
    if std == 0:
        z_scores = np.zeros(len(df))
    else:
        z_scores = np.abs((df['numeric_val'] - mean) / std)

    df = df[z_scores <= 2.5].copy()

    # 3. T-test
    if len(df) > 0:
        t_stat, p_val = stats.ttest_1samp(df['numeric_val'], 0.0)
        is_sig = bool(p_val < 0.05) if not np.isnan(p_val) else False
        df['is_significant'] = is_sig
    else:
        df['is_significant'] = False

    # 4. Tokenization
    all_tokens = []
    tokenized_rows = []
    for text in df['text_data']:
        if pd.isna(text):
            tokens = []
        else:
            tokens = str(text).lower().split()
        tokenized_rows.append(tokens)
        all_tokens.extend(tokens)

    counts = Counter(all_tokens)

    new_text = []
    for tokens in tokenized_rows:
        filtered = [t for t in tokens if counts[t] >= 3]
        new_text.append(" ".join(filtered))

    df['text_data'] = new_text

    # 5. Save as JSON
    df.to_json(out_json, orient='records')

if __name__ == '__main__':
    main()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
