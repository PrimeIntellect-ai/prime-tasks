#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libsm6 libxext6
    pip3 install --no-cache-dir pytest numpy opencv-python-headless scipy scikit-learn statsmodels pandas

    mkdir -p /app/corpus/train/clean
    mkdir -p /app/corpus/train/evil
    mkdir -p /app/corpus/test/clean
    mkdir -p /app/corpus/test/evil

    cat << 'EOF' > /tmp/setup.py
import os, numpy as np, cv2, hashlib

def generate_csv(path, label, n_rows=500):
    seed = int(hashlib.md5(path.encode()).hexdigest(), 16) % (2**32)
    np.random.seed(seed)
    temp = np.random.uniform(20, 80, n_rows)
    if label == 'clean':
        pressure = 3.5 * temp + 10.0 + np.random.normal(0, 2.0, n_rows)
    elif label == 'evil_slope':
        pressure = 3.8 * temp + 10.0 + np.random.normal(0, 2.0, n_rows)
    elif label == 'evil_int':
        pressure = 3.5 * temp + 16.0 + np.random.normal(0, 2.0, n_rows)
    elif label == 'evil_var':
        pressure = 3.5 * temp + 10.0 + np.random.normal(0, 8.0, n_rows)

    with open(path, 'w') as f:
        f.write("temperature,pressure\n")
        for t, p in zip(temp, pressure):
            f.write(f"{t:.4f},{p:.4f}\n")

# Generate train
for i in range(10): generate_csv(f'/app/corpus/train/clean/data_{i}.csv', 'clean')
for i in range(3): generate_csv(f'/app/corpus/train/evil/data_s_{i}.csv', 'evil_slope')
for i in range(3): generate_csv(f'/app/corpus/train/evil/data_i_{i}.csv', 'evil_int')
for i in range(3): generate_csv(f'/app/corpus/train/evil/data_v_{i}.csv', 'evil_var')

# Generate test (hidden)
for i in range(20): generate_csv(f'/app/corpus/test/clean/test_{i}.csv', 'clean')
for i in range(5): generate_csv(f'/app/corpus/test/evil/test_s_{i}.csv', 'evil_slope')
for i in range(5): generate_csv(f'/app/corpus/test/evil/test_i_{i}.csv', 'evil_int')
for i in range(5): generate_csv(f'/app/corpus/test/evil/test_v_{i}.csv', 'evil_var')

# Generate video
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/machine_monitor.mp4', fourcc, 10.0, (100, 100), False)
for i in range(100):
    val = int(100 + 50 * np.sin(i * 0.1))
    frame = np.full((100, 100), val, dtype=np.uint8)
    out.write(frame)
out.release()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
