#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    # Create the /app directory
    mkdir -p /app

    # Generate a dummy surveillance video file
    ffmpeg -f lavfi -i testsrc=duration=1:size=640x480:rate=30 -c:v libx264 -pix_fmt yuv420p /app/surveillance.mp4

    # Create the user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
