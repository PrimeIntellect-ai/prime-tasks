#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc python3-opencv
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate the video
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/fault_log.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (100, 100))
for i in range(300):
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    if i < 14:
        frame[:] = (255, 0, 0)  # BGR for solid blue (RGB: 0, 0, 255)
    else:
        frame[:] = (0, 255, 0)  # Green for other frames
    out.write(frame)
out.release()
EOF
    python3 /tmp/gen_video.py

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/test1.csv
1600000000,101,55.2,XYZ-998
1600000020,101,55.5,XYZ-998
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/test1.csv
1600000000,102,60.1,DROP TABLE;
1600000005,103,40.0,<script>alert()</script>
1600000010,104,45.0,VALID-12
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
