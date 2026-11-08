#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg rustc cargo curl wget
    pip3 install pytest numpy pandas opencv-python-headless

    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=5:size=640x480:rate=30 -pix_fmt yuv420p /app/experiment.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
