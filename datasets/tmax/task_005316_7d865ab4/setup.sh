#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential ffmpeg cargo rustc
    pip3 install pytest

    mkdir -p /app
    ffmpeg -f lavfi -i color=c=black:s=640x480:r=1:d=30 -c:v libx264 -y /tmp/base.mp4
    ffmpeg -f lavfi -i color=c=red:s=100x100 -frames:v 1 -y /tmp/red.png
    ffmpeg -i /tmp/base.mp4 -i /tmp/red.png -filter_complex "[0:v][1:v]overlay=x=10:y=10:enable='eq(t\,4)+eq(t\,15)+eq(t\,27)'" -c:v libx264 -y /app/ci_test_recording.mp4
    rm /tmp/base.mp4 /tmp/red.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
