#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg imagemagick bc jq curl
    pip3 install pytest flask fastapi uvicorn requests

    mkdir -p /app
    # Create a simple synthetic video
    ffmpeg -f lavfi -i color=c=gray:s=320x240:d=5 /app/dashcam.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
