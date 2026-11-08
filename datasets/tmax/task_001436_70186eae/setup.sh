#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gawk bc jq
    pip3 install pytest pandas numpy

    mkdir -p /app
    # Create a dummy video for the tests and agent to use
    ffmpeg -f lavfi -i testsrc=duration=5:size=320x240:rate=10 -c:v libx264 -y /app/experiment.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
