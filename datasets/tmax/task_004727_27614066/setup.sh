#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libglib2.0-0
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app

    # Create the oracle normalizer
    cat << 'EOF' > /app/oracle_normalizer
#!/usr/bin/env python3
import sys
import re

def eval_math(val):
    if re.match(r'^[0-9]+[\+\-\*][0-9]+$', val):
        try:
            return str(eval(val))
        except:
            return val
    return val

def main():
    if len(sys.argv) != 2:
        return
    query = sys.argv[1]
    pairs = []
    for part in query.split('&'):
        if '=' in part:
            k, v = part.split('=', 1)
            pairs.append((k, eval_math(v)))
        elif part:
            pairs.append((part, ''))

    pairs.sort(key=lambda x: x[0])
    out = []
    for k, v in pairs:
        out.append(f"{k}={v}")

    print("RED_17:" + "|".join(out))

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/oracle_normalizer

    # Generate the video
    cat << 'EOF' > /tmp/make_video.py
import cv2
import numpy as np
import random

frames = [True]*17 + [False]*83
random.seed(42)
random.shuffle(frames)

out = cv2.VideoWriter('/app/network_status.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (100, 100))
for is_red in frames:
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    if is_red:
        frame[:] = (0, 0, 255) # BGR for red
    out.write(frame)
out.release()
EOF
    python3 /tmp/make_video.py
    rm /tmp/make_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
