#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc ffmpeg libsm6 libxext6
    pip3 install pytest grpcio grpcio-tools opencv-python-headless

    # Create dummy video
    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 -pix_fmt yuv420p /app/drone_flight.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
