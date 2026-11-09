#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg golang
    pip3 install pytest

    # Create app directory and generate a test video
    mkdir -p /app
    ffmpeg -y -f lavfi -i testsrc=duration=10:size=320x240:rate=30 -pix_fmt yuv420p /app/video.mp4

    # Create required directories
    mkdir -p /tmp/frames
    chmod 777 /tmp/frames

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
