#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc ffmpeg
    pip3 install pytest numpy

    mkdir -p /app
    # Generate a dummy video for testing
    ffmpeg -f lavfi -i testsrc=duration=2:size=320x240:rate=5 -c:v libx264 /app/test_video.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
