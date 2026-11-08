#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest numpy watchdog Pillow opencv-python-headless

    mkdir -p /app
    # Generate a dummy video for the experiment
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 -pix_fmt yuv420p /app/experiment_feed.mp4

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/incoming /home/user/processed /home/user/chunks
    chmod -R 777 /home/user /app
