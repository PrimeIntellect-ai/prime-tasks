#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg
pip3 install pytest pillow

mkdir -p /app/data
mkdir -p /app/corpus/clean
mkdir -p /app/corpus/evil
mkdir -p /app/hidden_corpus/clean
mkdir -p /app/hidden_corpus/evil

# Generate video with anomaly from 12 to 18s
ffmpeg -y -f lavfi -i "testsrc=duration=30:size=640x480:rate=30" -vf "drawbox=x=100:y=100:w=100:h=100:color=red@1:t=fill:enable='between(t,12,18)'" -c:v libx264 -preset ultrafast -crf 28 /app/data/video.mp4

# Generate corpus using python
python3 -c '
import os
from PIL import Image, ImageDraw
import random

def make_img(path, is_evil):
    img = Image.new("RGB", (640, 480), color=(random.randint(0,200), random.randint(0,200), random.randint(0,200)))
    if is_evil:
        draw = ImageDraw.Draw(img)
        draw.rectangle([100, 100, 200, 200], fill="red")
    img.save(path)

for i in range(50):
    make_img(f"/app/corpus/clean/img_{i}.jpg", False)
    make_img(f"/app/corpus/evil/img_{i}.jpg", True)
    make_img(f"/app/hidden_corpus/clean/img_{i}.jpg", False)
    make_img(f"/app/hidden_corpus/evil/img_{i}.jpg", True)
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
