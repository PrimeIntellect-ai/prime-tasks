#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr g++
    pip3 install --no-cache-dir pytest pillow pandas numpy

    mkdir -p /app /home/user/data /home/user/output

    cat << 'EOF' > /tmp/setup.py
import os
import random
from PIL import Image, ImageDraw, ImageFont

os.makedirs('/home/user/data', exist_ok=True)
os.makedirs('/home/user/output', exist_ok=True)

# Generate Image
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 40), "Scoring coefficients: alpha=0.62, beta=1.15, gamma=0.04", fill=(0,0,0))
os.makedirs('/app', exist_ok=True)
img.save('/app/scoring_params.png')

# Generate FASTA
random.seed(42)
with open('/home/user/data/targets.fasta', 'w') as f:
    for i in range(1, 101):
        seq = "".join(random.choices(['A', 'C', 'G', 'T'], k=100))
        f.write(f">seq{i}\n{seq}\n")
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
