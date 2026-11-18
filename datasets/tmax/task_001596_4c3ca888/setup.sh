#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg cargo curl
    pip3 install pytest

    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=30:size=640x480:rate=30 -c:v libx264 /app/video_feed.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
