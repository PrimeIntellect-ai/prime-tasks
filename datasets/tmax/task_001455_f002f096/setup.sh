#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest pillow flask fastapi uvicorn requests

    # Create app data directory
    mkdir -p /app/data

    # Generate a dummy training video (5 seconds long)
    ffmpeg -f lavfi -i testsrc=duration=5:size=640x480:rate=30 -c:v libx264 -pix_fmt yuv420p /app/data/training_video.mp4

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
