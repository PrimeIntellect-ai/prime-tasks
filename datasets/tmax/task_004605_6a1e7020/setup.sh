#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        tesseract-ocr \
        golang-go \
        nodejs \
        npm \
        fonts-liberation

    pip3 install pytest Pillow

    # Create the video file
    mkdir -p /app
    cat << 'EOF' > /tmp/gen_video.py
from PIL import Image, ImageDraw, ImageFont
import subprocess

texts = [
    "legacy-v0.9.5",
    "legacy-v1.0.1",
    "legacy-v1.1.0",
    "legacy-v2.0.0-rc.1",
    "legacy-v2.0.0",
    "legacy-v3.1.2"
]

font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 40)

for i, text in enumerate(texts):
    img = Image.new('RGB', (800, 600), color=(255, 255, 255))
    d = ImageDraw.Draw(img)
    d.text((100, 100), text, fill=(0, 0, 0), font=font)
    for j in range(30):
        img.save(f"/tmp/frame_{i*30+j:04d}.png")

subprocess.run([
    "ffmpeg", "-y", "-framerate", "30", "-i", "/tmp/frame_%04d.png",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", "/app/archive_scroll.mp4"
], check=True)
EOF
    python3 /tmp/gen_video.py
    rm -f /tmp/frame_*.png /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/project_files
    chmod -R 777 /home/user
