#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest opencv-python-headless scikit-image

    # Create app directory and generate a dummy video
    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 -c:v libx264 -pix_fmt yuv420p /app/tutorial.mp4

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
