#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go ffmpeg sqlite3 curl
    pip3 install pytest

    mkdir -p /app/data /app/processed/frames /app/src

    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=1 -c:v libx264 /app/data/surveillance.mp4

    cat << 'EOF' > /app/data/events.csv
timestamp_sec,event_name,camera_id
0,car_passing,cam-1
1,person_walking,cam-1
2,dog_running,cam-1
3,bird_flying,cam-1
4,truck_passing,cam-1
5,bicycle_riding,cam-1
6,car_parking,cam-1
7,person_running,cam-1
8,cat_walking,cam-1
9,nothing,cam-1
EOF

    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
