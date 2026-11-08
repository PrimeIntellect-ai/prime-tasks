#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-liberation
    pip3 install pytest numpy scipy pandas

    mkdir -p /app/corpora/clean /app/corpora/evil

    # Update ImageMagick policy to allow text rendering if needed
    sed -i 's/<policy domain="path" rights="none" pattern="@\*"/<!-- <policy domain="path" rights="none" pattern="@\*" -->/g' /etc/ImageMagick-6/policy.xml || true

    convert -size 400x100 xc:white -fill black -pointsize 24 -gravity center -draw "text 0,0 'MAXIMUM_WASSERSTEIN_THRESHOLD: 4.25'" /app/profile_spec.png

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd
import os

latency_ms = np.arange(241)

def generate_profile(mu, sigma, path, bimodal=False):
    base = np.exp(-0.5 * ((latency_ms - mu) / sigma)**2)
    if bimodal:
        base = 0.8 * base + 0.2 * np.exp(-0.5 * ((latency_ms - 180) / 10)**2)
    noise = np.random.uniform(0, 0.1 * np.max(base), size=len(latency_ms))
    counts = base + noise
    counts = np.clip(counts, 0, None) * 1000
    df = pd.DataFrame({'latency_ms': latency_ms, 'counts': counts})
    df.to_csv(path, index=False)

np.random.seed(42)
for i in range(50):
    generate_profile(120, 20, f'/app/corpora/clean/profile_{i}.csv')

for i in range(50):
    if i % 2 == 0:
        generate_profile(135, 20, f'/app/corpora/evil/profile_{i}.csv')
    else:
        generate_profile(120, 20, f'/app/corpora/evil/profile_{i}.csv', bimodal=True)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
