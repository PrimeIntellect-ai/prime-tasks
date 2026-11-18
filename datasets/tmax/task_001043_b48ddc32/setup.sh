#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install --no-cache-dir pytest flask fastapi uvicorn pandas opencv-python-headless

    mkdir -p /app
    # Generate a dummy video file at 25 fps
    ffmpeg -f lavfi -i testsrc=duration=2:size=320x240:rate=25 -pix_fmt yuv420p /app/traffic_feed.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
