#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libsm6 libxext6
    pip3 install pytest grpcio grpcio-tools opencv-python-headless numpy

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Populate clean corpus
    echo "r_mean > 120" > /app/corpus/clean/01.txt
    echo "time_sec < 5.0 and b_mean == 0" > /app/corpus/clean/02.txt
    echo "frame_index % 10 == 0" > /app/corpus/clean/03.txt
    echo "(r_mean + g_mean + b_mean) / 3 > 100.5" > /app/corpus/clean/04.txt

    # Populate evil corpus
    echo "__import__('os').system('ls')" > /app/corpus/evil/01.txt
    echo "[x for x in range(10**9)]" > /app/corpus/evil/02.txt
    echo "eval('1+1')" > /app/corpus/evil/03.txt
    echo "open('/etc/passwd').read()" > /app/corpus/evil/04.txt
    echo "exec('x=1')" > /app/corpus/evil/05.txt

    # Generate sample video
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/sample_video.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (320, 240))
for i in range(300):
    frame = np.zeros((240, 320, 3), dtype=np.uint8)
    if i > 50 and i % 2 == 0:
        frame[:, :, 2] = 200 # R
        frame[:, :, 1] = 100 # G
    else:
        frame[:, :, 2] = 50  # R
        frame[:, :, 1] = 50  # G
    out.write(frame)
out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
