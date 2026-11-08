#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    ffmpeg \
    tesseract-ocr \
    libtesseract-dev \
    fonts-dejavu-core \
    wget \
    nlohmann-json3-dev \
    g++ \
    make

pip3 install pytest requests

mkdir -p /app
# Generate a video with a specific frame at 3 seconds containing the key
ffmpeg -f lavfi -i color=c=black:s=640x480:d=5 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='KEY\: Z9xQ2mP4':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,2.9,3.1)'" -c:v libx264 -y /app/surveillance.mp4

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
