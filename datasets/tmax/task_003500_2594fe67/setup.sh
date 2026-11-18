#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg g++
    pip3 install pytest pandas numpy

    mkdir -p /app
    # Generate a dummy video for the task quickly
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 -c:v libx264 -preset ultrafast -pix_fmt yuv420p /app/traffic_camera.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
