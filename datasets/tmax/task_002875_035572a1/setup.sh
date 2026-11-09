#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg fonts-liberation
    pip3 install pytest

    mkdir -p /app

    # Generate video
    echo "./evader.py --payload \"<script>alert('XSS')</script>\" --xor-key 0x4B --output hex" > /tmp/text.txt
    ffmpeg -f lavfi -i color=c=black:s=1280x720:r=30:d=5 -vf "drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf:textfile=/tmp/text.txt:fontcolor=white:fontsize=24:x=50:y=50:enable='between(t,2,5)'" -c:v libx264 -y /app/attack_session.mp4

    # Generate corpora
    cat << 'EOF' > /tmp/setup.py
import os

os.makedirs('/app/corpora/evil', exist_ok=True)
os.makedirs('/app/corpora/clean', exist_ok=True)

evil_payloads = ["1' OR '1'='1", "<img src=x onerror=alert(1)>", "admin' --", "<script>alert('XSS')</script>"]
clean_payloads = ["hello world", "this is a test", "benign data", "just some normal text"]

def encode(text, key):
    return bytes([b ^ key for b in text.encode()]).hex()

for i, p in enumerate(evil_payloads):
    with open(f'/app/corpora/evil/evil_{i}.txt', 'w') as f:
        f.write(encode(p, 0x4B))

for i, p in enumerate(clean_payloads):
    with open(f'/app/corpora/clean/clean_{i}.txt', 'w') as f:
        f.write(encode(p, 0x4B))
EOF
    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
