#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy opencv-python-headless pandas

    mkdir -p /app/evil_corpus
    mkdir -p /app/clean_corpus

    # Generate video fixture
    cat << 'EOF' > /tmp/generate_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/telemetry_dashboard.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (200, 200))
for i in range(300):
    frame = np.zeros((200, 200, 3), dtype=np.uint8)
    if (i // 10) % 2 == 1:
        frame[0:50, 0:50, 2] = 255 # Red channel in BGR is index 2
    out.write(frame)
out.release()
EOF
    python3 /tmp/generate_video.py

    # Generate clean corpus
    cat << 'EOF' > /app/clean_corpus/clean1.jsonl
{"timestamp": 1000, "value": 42}
{"timestamp": 1020, "value": 43}
{"timestamp": 1050, "value": 44}
EOF

    # Generate evil corpus
    cat << 'EOF' > /app/evil_corpus/evil1.jsonl
{"timestamp": 1000, "value": 42}
{"timestamp": 1000, "value": 42}
{"timestamp": 1005, "value": 42}
{"timestamp": 1020, "value": 43, "bad_unicode": "\uD83D\uDE0"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
