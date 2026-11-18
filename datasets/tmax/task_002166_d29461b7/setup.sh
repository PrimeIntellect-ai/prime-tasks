#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install --default-timeout=100 pytest numpy opencv-python-headless flask scipy

    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=20:size=320x240:rate=30 -c:v libx264 -y /app/traffic_camera.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
