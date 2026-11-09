#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy opencv-python-headless scipy matplotlib flask fastapi uvicorn requests

    mkdir -p /app
    mkdir -p /home/user

    # Create video generation script
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np
import math

fps = 60
duration = 2
frames = fps * duration

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/experiment.mp4', fourcc, fps, (256, 256))

for i in range(frames):
    t = i / fps
    x = int(100 * math.sin(2 * math.pi * 4.5 * t) + 128)
    frame = np.zeros((256, 256, 3), dtype=np.uint8)
    cv2.circle(frame, (x, 128), 5, (255, 255, 255), -1)
    out.write(frame)

out.release()
EOF

    python3 /tmp/gen_video.py

    # Create buggy simulation script
    cat << 'EOF' > /home/user/sim_parallel.py
import multiprocessing
import random
import math

def simulate_sample(index):
    # Simulate some complex chaotic calculation
    random.seed(index)
    val = sum(math.sin(random.random()) for _ in range(1000))
    return index, val

def main():
    pool = multiprocessing.Pool(processes=4)
    total_energy = 0.0
    # BUG: using imap_unordered causes results to arrive in random order
    # Adding floating point numbers in different orders causes drift
    for index, val in pool.imap_unordered(simulate_sample, range(2000)):
        total_energy += val
    pool.close()
    pool.join()
    return total_energy

if __name__ == "__main__":
    print(main())
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
