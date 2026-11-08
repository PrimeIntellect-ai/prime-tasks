#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app
    # Generate a dummy video file
    ffmpeg -f lavfi -i color=c=black:s=128x128:r=30:d=48 -c:v libx264 -y /app/surveillance_feed.mp4

    mkdir -p /home/user/service
    python3 -c '
with open("/home/user/service/state.wal", "wb") as f:
    f.write(bytes([0xAA, 0x44, 0x53, 0x40, 0x00, 0xBB]))
'

    mkdir -p /home/user/metadata/clean
    mkdir -p /home/user/metadata/evil

    for i in $(seq 1 50); do
        echo '{"timestamp": 123456789, "bbox": [10, 20, 30, 40]}' > /home/user/metadata/clean/file_$i.json
        echo '{"timestamp": 123456789, "bbox": {"bbox": {"bbox": {"bbox": {"bbox": {"bbox": {"bbox": [10, 20, 30, 40]}}}}}}}}' > /home/user/metadata/evil/file_$i.json
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
