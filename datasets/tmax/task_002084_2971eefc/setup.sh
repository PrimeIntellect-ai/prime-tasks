#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc
    pip3 install pytest

    mkdir -p /app
    # Generate a dummy video file with ffmpeg
    ffmpeg -f lavfi -i testsrc=duration=10:size=320x240:rate=10 -c:v libx264 /app/sensor_feed.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
