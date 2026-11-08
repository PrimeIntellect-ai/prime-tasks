#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev ffmpeg
    pip3 install pytest

    # Create required directories
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate the video fixture (20 seconds, 25 fps = 500 frames)
    ffmpeg -f lavfi -i testsrc=duration=20:size=640x480:rate=25 -c:v libx264 /app/dataset_video.mp4

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
