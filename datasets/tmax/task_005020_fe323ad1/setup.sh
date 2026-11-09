#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app

    # Create oracle
    cat << 'EOF' > /app/oracle_integrator
#!/usr/bin/env python3
import sys

def main():
    S_prev = None
    I_prev = 0.0
    dt = 0.1

    x_hist = []

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            x = float(line)
        except ValueError:
            continue

        x_hist.append(x)
        if len(x_hist) > 3:
            x_hist.pop(0)

        n = len(x_hist)
        S_t = sum(x_hist) / n

        if n == 1:
            I_t = 0.0
        else:
            I_t = I_prev + dt * (S_t + S_prev) / 2.0

        print(f"{I_t:.4f}")
        sys.stdout.flush()

        S_prev = S_t
        I_prev = I_t

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle_integrator

    # Generate video
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/led_strobe.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (100, 100))

for i in range(200):
    if i < 142:
        val = np.random.randint(50, 200)
    else:
        val = np.random.randint(4, 10)
    frame = np.full((100, 100, 3), val, dtype=np.uint8)
    out.write(frame)

out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
