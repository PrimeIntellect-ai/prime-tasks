#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest numpy pandas flask fastapi uvicorn ffmpeg-python requests

    # Create directories
    mkdir -p /app
    mkdir -p /home/user

    # Generate test video
    ffmpeg -y -f lavfi -i testsrc=duration=60:size=640x480:rate=30 -c:v libx264 /app/security_feed.mp4

    # Generate sensor logs CSV
    echo "timestamp_sec,sensor_active" > /home/user/sensor_logs.csv
    for i in $(seq 0 59); do
        echo "$i,$((i % 2))" >> /home/user/sensor_logs.csv
    done

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
