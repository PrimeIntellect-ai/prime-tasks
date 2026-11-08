#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg cron
    pip3 install pytest opencv-python-headless pandas numpy

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /app/corpus/clean/data1.json
{"timestamp": 12.5, "frame_id": 10, "bbox": [10, 20, 50, 60], "confidence": 0.95}
{"timestamp": 12.6, "frame_id": 11, "bbox": [12, 22, 52, 62], "confidence": 0.88}
EOF

    cat << 'EOF' > /app/corpus/evil/bad1.json
{"timestamp": -5.0, "frame_id": 12, "bbox": [10, 20, 50, 60], "confidence": 0.95}
{"timestamp": 12.6, "frame_id": -1, "bbox": [12, 22, 52, 62], "confidence": 0.88}
{"timestamp": 12.7, "frame_id": 13, "bbox": [12, 22, 52], "confidence": 0.88}
{"timestamp": 12.8, "frame_id": 14, "bbox": [12, 22, 52, "bad"], "confidence": 0.88}
{"timestamp": 12.9, "frame_id": 15, "bbox": [12, 22, 52, 62], "confidence": 1.5}
EOF

    ffmpeg -f lavfi -i testsrc=duration=5:size=640x480:rate=30 -c:v libx264 /app/traffic.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
