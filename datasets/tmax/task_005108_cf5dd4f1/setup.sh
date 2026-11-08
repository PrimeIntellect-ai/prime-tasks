#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc zlib1g-dev
    pip3 install pytest

    # Create app directory
    mkdir -p /app

    # Generate a dummy video file
    ffmpeg -f lavfi -i testsrc=duration=5:size=320x240:rate=10 -c:v libx264 /app/video.mp4

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/chunks
    chmod -R 777 /home/user
    chmod -R 777 /app
