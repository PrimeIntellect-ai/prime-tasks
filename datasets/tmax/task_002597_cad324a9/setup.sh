#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app
    # Generate a 10-second sample video
    ffmpeg -f lavfi -i testsrc=duration=10:size=320x240:rate=30 -c:v libx264 /app/experiment_record.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
