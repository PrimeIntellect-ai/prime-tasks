#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest requests flask fastapi uvicorn

    mkdir -p /app
    # Generate a 5-second video at 30 fps (150 frames)
    ffmpeg -y -f lavfi -i testsrc=duration=5:size=640x480:rate=30 -pix_fmt yuv420p /app/surveillance.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
