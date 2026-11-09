#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg netcat-openbsd socat curl
    pip3 install pytest opencv-python-headless numpy scipy

    # Create the /app directory and generate a deterministic test video
    mkdir -p /app
    ffmpeg -y -f lavfi -i testsrc=duration=2:size=320x240:rate=10 -pix_fmt yuv420p /app/experiment.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
