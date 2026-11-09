#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install --no-cache-dir pytest scipy numpy opencv-python-headless flask requests

    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=1 -c:v libx264 /app/traffic.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
