#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc
    pip3 install pytest

    mkdir -p /app
    # Generate a 10-second video at 10 fps (100 frames)
    ffmpeg -f lavfi -i testsrc=duration=10:size=64x64:rate=10 -pix_fmt yuv420p /app/experiment.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
