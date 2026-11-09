#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr
    pip3 install pytest opencv-python-headless pytesseract pandas "numpy<2"

    mkdir -p /app
    cat << 'EOF' > /tmp/generate_video.py
import cv2
import numpy as np
import os
import math
import pandas as pd

os.makedirs('/app', exist_ok=True)
output_file = '/app/server_logs.mp4'
fps = 1
duration = 60
width, height = 640, 200

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter(output_file, fourcc, fps, (width, height))

np.random.seed(42)
base_cpu = 40.0

ground_truth_cpu = []

for sec in range(1, duration + 1):
    # Create a noisy sine wave for CPU
    cpu_val = base_cpu + 20 * math.sin(sec / 5.0) + np.random.normal(0, 2.0)
    cpu_val = round(cpu_val, 1)
    ground_truth_cpu.append(cpu_val)

    # Create image
    img = np.zeros((height, width, 3), dtype=np.uint8)

    # Text to display
    text = f"[DEBUG] seq: {sec:03d} | CPU_USAGE: {cpu_val}% | RAM: 1024M"

    # Add text to image
    font = cv2.FONT_HERSHEY_SIMPLEX
    cv2.putText(img, text, (20, 100), font, 0.8, (255, 255, 255), 2, cv2.LINE_AA)

    out.write(img)

out.release()

# Save ground truth for the verifier
df = pd.DataFrame({'second': range(1, 61), 'cpu': ground_truth_cpu})
df['smoothed_cpu_gt'] = df['cpu'].rolling(window=5, min_periods=1).mean()
df.to_csv('/app/gt_smoothed.csv', index=False)
EOF

    python3 /tmp/generate_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
