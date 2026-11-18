#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg cron
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app/corpora/clean /app/corpora/evil

    # Generate video with 7 black frames
    python3 -c "
import cv2
import numpy as np

out = cv2.VideoWriter('/app/trailer.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (640, 480))
for i in range(300):
    if i < 7:
        frame = np.zeros((480, 640, 3), dtype=np.uint8)
    else:
        frame = np.ones((480, 640, 3), dtype=np.uint8) * 255
    out.write(frame)
out.release()
"

    # Populate clean corpus
    cat << 'EOF' > /app/corpora/clean/file1.txt
Welcome to the <b>Arena</b>!
Health: <color=#FF0000>Critical</color>
<i>Press Start</i>
EOF

    # Populate evil corpus
    cat << 'EOF' > /app/corpora/evil/file1.txt
Welcome to the <script>alert(1)</script> Arena!
Health: <color=red>Critical</color>
<b>Unclosed bold tag
Level Up! <img src="x" onerror="crash()">
EOF

    # Populate staging
    cat << 'EOF' > /app/staging.txt
<b>Valid Staging</b>
<script>Invalid Staging</script>
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
