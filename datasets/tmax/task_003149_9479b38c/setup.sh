#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-opencv ffmpeg
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpora/evil/evil_1
    mkdir -p /app/corpora/evil/evil_2/assets
    mkdir -p /app/corpora/evil/evil_3
    mkdir -p /app/corpora/clean/clean_1
    mkdir -p /app/corpora/clean/clean_2

    # Generate corpora
    head -c 100001 /dev/zero > /app/corpora/evil/evil_1/data.txt
    touch /app/corpora/evil/evil_2/assets/video.mp4
    echo -e "Some logs\n[COST_ALERT: MASSIVE_LOG]\nEnd logs" > /app/corpora/evil/evil_3/logs.txt

    head -c 99999 /dev/zero > /app/corpora/clean/clean_1/data.txt
    touch /app/corpora/clean/clean_2/image.png
    echo "print('hello')" > /app/corpora/clean/clean_2/script.py
    echo "# Doc" > /app/corpora/clean/clean_2/doc.md

    # Generate video
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/dashboard_recording.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (320, 240))
for i in range(200):
    frame = np.zeros((240, 320, 3), dtype=np.uint8)
    if 145 <= i <= 160:
        # OpenCV uses BGR
        frame[0:100, 0:100] = (0, 0, 255)
    out.write(frame)
out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
