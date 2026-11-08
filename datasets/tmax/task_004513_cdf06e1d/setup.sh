#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ tesseract-ocr
    pip3 install --default-timeout=100 pytest numpy Pillow pandas

    mkdir -p /app
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Create directories
os.makedirs('/app', exist_ok=True)
os.makedirs('/home/user', exist_ok=True)

# 1. Generate image fixture
img = Image.new('RGB', (300, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
# Use a default font or standard linux font if available
d.text((10,10), "WINDOW=11\nALPHA=0.25", fill=(0,0,0))
img.save('/app/cleaning_params.png')

# 2. Generate noisy time series
np.random.seed(42)
start_time = 1600000000
num_points = 50000

timestamps = [start_time]
values = [np.sin(0) + np.random.normal(0, 0.5)]

curr_time = start_time
for i in range(1, num_points):
    # Irregular steps: 1, 2, or 3 seconds
    step = np.random.choice([1, 2, 3])
    curr_time += step
    val = np.sin(i * 0.001) + np.random.normal(0, 0.5)
    timestamps.append(curr_time)
    values.append(val)

with open('/app/noisy_sensor.csv', 'w') as f:
    for t, v in zip(timestamps, values):
        f.write(f"{t},{v:.4f}\n")

# 3. Generate canonical solution for the verifier
reg_timestamps = list(range(timestamps[0], timestamps[-1] + 1))
reg_values = []
idx = 0
for t in reg_timestamps:
    while idx < len(timestamps) - 1 and timestamps[idx + 1] <= t:
        idx += 1
    reg_values.append(values[idx])

window = 11
half_w = window // 2
n = len(reg_values)
rolling_means = np.zeros(n)
for i in range(n):
    start = max(0, i - half_w)
    end = min(n, i + half_w + 1)
    rolling_means[i] = np.mean(reg_values[start:end])

alpha = 0.25
ema = np.zeros(n)
ema[0] = rolling_means[0]
for i in range(1, n):
    ema[i] = alpha * rolling_means[i] + (1 - alpha) * ema[i-1]

with open('/app/canonical_clean.csv', 'w') as f:
    for t, v in zip(reg_timestamps, ema):
        f.write(f"{t},{v:.4f}\n")
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
