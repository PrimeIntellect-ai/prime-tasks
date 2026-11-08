#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg wget tar
    pip3 install pytest numpy opencv-python-headless

    # Install Go 1.21
    wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
    rm go1.21.6.linux-amd64.tar.gz
    ln -s /usr/local/go/bin/go /usr/bin/go
    ln -s /usr/local/go/bin/gofmt /usr/bin/gofmt

    # Generate datasets and corpora
    cat << 'EOF' > /tmp/generate_data.py
import cv2
import numpy as np
import os
import csv
import random

os.makedirs('/app/dataset', exist_ok=True)
os.makedirs('/app/corpora/clean', exist_ok=True)
os.makedirs('/app/corpora/evil', exist_ok=True)

# 1. sensor_time.csv
with open('/app/dataset/sensor_time.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['frame_id', 'timestamp_ms'])
    for i in range(60):
        writer.writerow([i, int(i * 1000 / 30)])

# 2. pendulum.mp4
out = cv2.VideoWriter('/app/dataset/pendulum.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (640, 480), False)
for i in range(60):
    frame = np.zeros((480, 640), dtype=np.uint8)
    # Pendulum motion
    x = int(320 + 100 * np.sin(i * 0.2))
    y = int(240 + 50 * np.cos(i * 0.2))
    if i == 15: # Spike
        x += 200
    cv2.circle(frame, (x, y), 20, 255, -1)
    out.write(frame)
out.release()

# 3. Corpora generation
def generate_corpus(path, is_evil):
    for i in range(50):
        with open(f'{path}/data_{i}.csv', 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['t', 'val'])
            # Base signal with random spike
            signal = [random.uniform(0, 10) for _ in range(100)]
            spike_idx = random.randint(20, 80)
            signal[spike_idx] += 100

            smoothed = []
            for t in range(100):
                if is_evil:
                    start = max(0, t - 2)
                    end = min(100, t + 3)
                    val = sum(signal[start:end]) / (end - start)
                else:
                    start = max(0, t - 4)
                    val = sum(signal[start:t+1]) / (t + 1 - start)
                smoothed.append(val)

            for t in range(100):
                writer.writerow([t, smoothed[t]])

generate_corpus('/app/corpora/clean', False)
generate_corpus('/app/corpora/evil', True)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/pipeline /home/user/bin
    chmod -R 777 /home/user /app
