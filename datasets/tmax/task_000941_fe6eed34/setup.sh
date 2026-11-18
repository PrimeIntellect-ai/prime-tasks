#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libsm6 libxext6
    pip3 install pytest opencv-python-headless numpy

    # Create directories
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/mixed_logs

    # Generate clean logs
    cat << 'EOF' > /app/corpus/clean/clean1.json
{"timestamp": "2023-10-01T12:00:00Z", "service_name": "auth-service", "cpu_usage": 45.5}
EOF
    cat << 'EOF' > /app/corpus/clean/clean2.json
{"timestamp": "2023-10-01T12:01:00Z", "service_name": "db-backend", "cpu_usage": 99.9}
EOF

    # Generate evil logs
    cat << 'EOF' > /app/corpus/evil/evil1.json
{"timestamp": "2023-10-01T12:02:00Z", "service_name": "db-backend;", "cpu_usage": 50}
EOF
    cat << 'EOF' > /app/corpus/evil/evil2.json
{"timestamp": "2023-10-01T12:03:00Z", "service_name": "auth", "cpu_usage": 105}
EOF
    cat << 'EOF' > /app/corpus/evil/evil3.json
{"timestamp": "2023-10-01T12:04:00Z", "service_name": "auth", "cpu_usage": "high"}
EOF
    cat << 'EOF' > /app/corpus/evil/evil4.json
{"timestamp": "2023-10-01T12:05:00Z", "service_name": "auth"}
EOF
    cat << 'EOF' > /app/corpus/evil/evil5.json
This is not JSON
EOF

    # Copy to mixed_logs
    cp /app/corpus/clean/* /app/corpus/mixed_logs/
    cp /app/corpus/evil/* /app/corpus/mixed_logs/

    # Generate video
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/dashboard_recording.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (200, 200))
for i in range(50):
    frame = np.zeros((200, 200, 3), dtype=np.uint8)
    if i < 27:
        # Red flash in top-right 100x100 (x: 100-200, y: 0-100)
        # OpenCV uses BGR, so Red is index 2
        frame[0:100, 100:200] = [0, 0, 200]
    out.write(frame)
out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
