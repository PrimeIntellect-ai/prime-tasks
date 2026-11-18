#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg python3-opencv
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil

    # Generate video with 14 blue frames
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/deployment_test_feed.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (100, 100))
for i in range(30):
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    if i < 14:
        frame[:] = (255, 0, 0) # BGR: pure blue
    out.write(frame)
out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    # Generate corpora
    cat << 'EOF' > /app/corpora/clean/log1.json
{"timestamp": "2023-10-01T12:00:00Z", "locale": "en_US.UTF-8", "timezone": "America/New_York"}
EOF
    cat << 'EOF' > /app/corpora/clean/log2.json
{"timestamp": "2023-10-01T12:00:00Z", "locale": "fr_FR.UTF-8", "timezone": "Europe/Paris"}
EOF

    cat << 'EOF' > /app/corpora/evil/log1.json
{"timestamp": "2023-10-01T12:00:00Z", "locale": "en_US.UTF-8;", "timezone": "America/New_York"}
EOF
    cat << 'EOF' > /app/corpora/evil/log2.json
{"timestamp": "2023-10-01T12:00:00Z", "locale": "$(reboot)", "timezone": "America/New_York"}
EOF
    cat << 'EOF' > /app/corpora/evil/log3.json
{"timestamp": "2023-10-01T12:00:00Z", "locale": "en_US.UTF-8", "timezone": "../../../etc/passwd"}
EOF

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_monitor
    echo '{"version": "1.0"}' > /home/user/legacy_monitor/config.json

    chmod -R 777 /home/user
    chmod -R 777 /app
