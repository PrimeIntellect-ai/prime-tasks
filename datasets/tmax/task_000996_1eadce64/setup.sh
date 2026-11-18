#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc libc6-dev curl
    pip3 install pytest

    mkdir -p /app

    # Create a dummy 10-second video file at 24fps
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=24 -c:v libx264 /app/traffic_feed.mp4

    # Create the radar sensors CSV
    cat <<EOF > /app/radar_sensors.csv
timestamp_sec,noisy_speed_mph,prior_prob_speeding
0,65.2,0.1
1,70.1,0.3
2,85.5,0.8
3,60.0,0.05
4,75.2,0.5
5,80.1,0.7
6,68.9,0.2
7,72.3,0.4
8,90.0,0.9
9,62.1,0.1
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
