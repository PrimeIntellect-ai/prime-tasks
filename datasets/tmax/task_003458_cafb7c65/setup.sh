#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg
pip3 install --default-timeout=100 pytest requests fastapi uvicorn httpx

mkdir -p /app
ffmpeg -f lavfi -i testsrc=duration=3:size=640x360:rate=30 -c:v libx264 /app/project_video.mp4

useradd -m -s /bin/bash user || true
mkdir -p /home/user/app
chmod -R 777 /home/user
chmod -R 777 /app
