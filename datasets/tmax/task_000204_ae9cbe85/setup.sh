#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest opencv-python-headless pandas scikit-learn flask fastapi uvicorn requests

    mkdir -p /app

    # Generate video
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=24 -c:v libx264 /app/experiment_feed.mp4

    # Generate sensor_logs.csv
    cat << 'EOF' > /app/sensor_logs.csv
timestamp,temp,pressure,humidity,target_yield
0,20.0,1.0,50,10.0
1,21.0,1.1,51,11.0
2,22.0,1.2,52,12.0
3,23.0,1.3,53,13.0
4,24.0,1.4,54,14.0
5,25.0,1.5,55,15.0
6,26.0,1.6,56,16.0
7,27.0,1.7,57,17.0
8,28.0,1.8,58,18.0
9,29.0,1.9,59,19.0
10,30.0,2.0,60,20.0
EOF

    # Generate metadata.json
    cat << 'EOF' > /app/metadata.json
{"offset": 0}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
