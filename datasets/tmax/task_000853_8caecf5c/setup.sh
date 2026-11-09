#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    # Create dummy video for the task
    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=15:size=640x480:rate=30 -c:v libx264 /app/dashcam.mp4

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
