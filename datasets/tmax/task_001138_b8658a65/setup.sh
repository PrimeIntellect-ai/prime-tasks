#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-opencv ffmpeg
    pip3 install pytest numpy

    mkdir -p /app/corpora/clean /app/corpora/evil

    cat << 'EOF' > /tmp/make_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/dashboard.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (640, 480))
for frame_idx in range(300):
    img = np.zeros((480, 640, 3), dtype=np.uint8)
    sec = frame_idx // 30
    ts = 1715000000 + sec
    cv2.putText(img, str(ts), (50, 240), cv2.FONT_HERSHEY_SIMPLEX, 2, (255, 255, 255), 3)
    if 120 <= frame_idx < 210:
        cv2.putText(img, "OVERLOAD", (50, 340), cv2.FONT_HERSHEY_SIMPLEX, 2, (0, 0, 255), 3)
    out.write(img)
out.release()
EOF
    python3 /tmp/make_video.py

    for i in $(seq 1 10); do
        cat << 'EOF' > /app/corpora/clean/log_$i.txt
1715000001 104.1234 OK
1715000002 105.12 OK
1715000003 99.9999 FAIL
1715000008 100.0 OK
EOF
        cat << 'EOF' > /app/corpora/evil/log_$i.txt
1715000001 104.1234 OK
1715000004 105.12 OK
1715000005 106.12 OK
1715000006 107.12 OK
1715000002 105.123456 OK
1715000003 1.05e2 OK
1715000008 100.0 OK
1715000009 12.56789 FAIL
EOF
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
