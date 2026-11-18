#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc libc6-dev
    pip3 install pytest

    mkdir -p /app
    # Generate a dummy video file with exactly 24 FPS
    ffmpeg -f lavfi -i testsrc=duration=2:size=160x120:rate=24 -c:v libx264 -pix_fmt yuv420p /app/stream.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
