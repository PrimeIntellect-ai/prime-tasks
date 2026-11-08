#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr fonts-liberation
    pip3 install pytest Pillow

    mkdir -p /app

    # Create the video fixture
    cat << 'EOF' > /app/generate_video.py
import os
import subprocess
from PIL import Image, ImageDraw, ImageFont

os.makedirs('/app/frames', exist_ok=True)
ids = [f"uid_{i:08x}" for i in range(50)]
with open('/app/ground_truth.txt', 'w') as f:
    for uid in ids:
        f.write(uid + '\n')

try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 48)
except:
    font = ImageFont.load_default()

for i, uid in enumerate(ids):
    img = Image.new('RGB', (640, 480), color='white')
    d = ImageDraw.Draw(img)
    d.text((200, 200), uid, fill='black', font=font)
    img.save(f'/app/frames/frame_{i:03d}.png')

subprocess.run(['ffmpeg', '-y', '-framerate', '1', '-i', '/app/frames/frame_%03d.png', '-c:v', 'libx264', '-r', '30', '-pix_fmt', 'yuv420p', '/app/target_ids.mp4'], check=True)
EOF

    python3 /app/generate_video.py
    rm -rf /app/frames /app/generate_video.py

    # Create the verifier script
    cat << 'EOF' > /app/verifier.py
import base64
import json
import sys

def decode_b64(val):
    val += '=' * (-len(val) % 4)
    return base64.urlsafe_b64decode(val).decode('utf-8')

def verify():
    with open('/app/ground_truth.txt', 'r') as f:
        ground_truth = set(line.strip() for line in f if line.strip())

    try:
        with open('/home/user/forged_tokens.txt', 'r') as f:
            tokens = [line.strip() for line in f if line.strip()]
    except FileNotFoundError:
        print("0.0")
        return

    valid_count = 0
    for token in tokens:
        parts = token.split('.')
        if len(parts) != 3:
            continue
        header, payload, signature = parts
        if signature != "":
            continue
        try:
            h = json.loads(decode_b64(header))
            p = json.loads(decode_b64(payload))
            if h.get('alg', '').lower() == 'none' and p.get('role') == 'admin' and p.get('user_id') in ground_truth:
                valid_count += 1
        except:
            continue

    score = valid_count / len(ground_truth) if ground_truth else 0.0
    print(score)

if __name__ == '__main__':
    verify()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
