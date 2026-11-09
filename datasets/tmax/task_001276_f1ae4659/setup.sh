#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git tesseract-ocr fonts-dejavu-core
    pip3 install pytest Pillow

    mkdir -p /app

    # Generate the alert image using Pillow
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (600, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 24)
except:
    font = ImageFont.load_default()
d.text((10, 30), 'TOLERANCE_THRESHOLD=0.0000000005', fill=(0, 0, 0), font=font)
img.save('/app/alert.png')
"

    # Create the git repository
    mkdir -p /home/user/repo
    cd /home/user/repo
    git init
    git config --global user.email "dev@example.com"
    git config --global user.name "Dev"

    # Initial commit
    cat << 'EOF' > aggregate.py
import math
import json
def compute(data):
    return math.fsum(data)
EOF
    git add aggregate.py
    git commit -m "Initial commit: correct implementation"

    # 150 dummy commits
    for i in $(seq 1 150); do
        echo "Dummy commit $i" > README.md
        git add README.md
        git commit -m "Dummy commit $i"
    done

    # Buggy commit
    cat << 'EOF' > aggregate.py
import json
def compute(data):
    # Optimized for speed
    ans = 0.0
    for x in data:
        ans += x
    return ans
EOF
    git add aggregate.py
    git commit -m "Optimize compute function"

    # 49 dummy commits
    for i in $(seq 1 49); do
        echo "Dummy commit post-bug $i" > README.md
        git add README.md
        git commit -m "Dummy commit post-bug $i"
    done

    # Generate corpora
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    python3 -c "
import json, random
for i in range(20):
    clean_data = [random.random() for _ in range(100)]
    with open(f'/app/corpus/clean/test_{i}.json', 'w') as f:
        json.dump(clean_data, f)
    evil_data = [1e16, 1.1, -1e16]
    with open(f'/app/corpus/evil/test_{i}.json', 'w') as f:
        json.dump(evil_data, f)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
