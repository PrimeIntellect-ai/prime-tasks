#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg golang-go
    pip3 install pytest

    # Create directories
    mkdir -p /app/data

    # Generate a 5-second 30fps MP4 video fixture
    ffmpeg -f lavfi -i testsrc=duration=5:size=640x360:rate=30 -c:v libx264 /app/data/raw_footage.mp4

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
