#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc
pip3 install pytest

mkdir -p /app
# Generate a solid color video with hex 9F9F9F (approx 159 grayscale intensity)
# 159 / 255 * 100 = 62.35%
ffmpeg -f lavfi -i color=c=0x9F9F9F:s=640x480:d=2 -pix_fmt yuv420p -c:v libx264 /app/server_load.mp4

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
