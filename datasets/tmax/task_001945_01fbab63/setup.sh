#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tar coreutils
    pip3 install pytest

    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    # Generate a dummy video of 5 seconds
    ffmpeg -y -f lavfi -i testsrc=duration=5:size=1280x720:rate=30 -c:v libx264 /app/demo_video.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
