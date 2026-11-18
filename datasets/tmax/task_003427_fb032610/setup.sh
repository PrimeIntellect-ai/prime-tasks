#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg golang
    pip3 install pytest

    mkdir -p /app
    # Create a dummy video file for the initial state test.
    # The actual test framework may overwrite this with the real video.
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=5 -c:v libx264 /app/broadcast.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
