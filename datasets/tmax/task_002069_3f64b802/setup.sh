#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg nginx curl
    pip3 install pytest flask fastapi uvicorn gunicorn opencv-python-headless

    # Generate the video fixture
    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 -vf "drawbox=x=0:y=0:w=640:h=480:color=red@1.0:t=fill:enable='eq(n,142)'" -c:v libx264 -pix_fmt yuv420p /app/anomaly_feed.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
