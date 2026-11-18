#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr fonts-dejavu
    pip3 install pytest numpy matplotlib pytesseract Pillow

    mkdir -p /app/corpus/clean /app/corpus/evil

    # 1. Generate the image fixture
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 36 -fill black -draw "text 20,60 'THRESHOLD=0.85'" /app/threshold_image.png

    # 2. Generate the corpora
    cat << 'EOF' > /tmp/gen_corpus.py
import numpy as np
import os

np.random.seed(42)

# Clean: 10 files, random noise, correlations ~ 0.1 max
os.makedirs('/app/corpus/clean', exist_ok=True)
for i in range(10):
    data = np.random.randn(200, 50)
    np.save(f'/app/corpus/clean/clean_{i}.npy', data)

# Evil: 10 files, high correlation in two columns (>0.85)
os.makedirs('/app/corpus/evil', exist_ok=True)
for i in range(10):
    data = np.random.randn(200, 50)
    # Inject high correlation (0.9 weight)
    data[:, 5] = data[:, 2] * 0.9 + np.random.randn(200) * 0.1
    np.save(f'/app/corpus/evil/evil_{i}.npy', data)
EOF
    python3 /tmp/gen_corpus.py

    # 3. Generate the broken plot script
    cat << 'EOF' > /app/plot_correlations.py
import numpy as np
import matplotlib
# Missing matplotlib.use('Agg') causes issues in headless setups if interactive backend is default
import matplotlib.pyplot as plt

def plot_data():
    data = np.random.randn(50, 10)
    corr = np.corrcoef(data, rowvar=False)
    plt.imshow(corr, cmap='hot')
    plt.savefig('/home/user/correlation.png')
    # Intentionally bad config, might require user to fix backend or plt.show() logic

if __name__ == '__main__':
    plot_data()
EOF
    chmod +x /app/plot_correlations.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
