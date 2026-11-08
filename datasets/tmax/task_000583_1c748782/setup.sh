#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr golang-go

    pip3 install pytest opencv-python-headless pillow numpy pandas

    mkdir -p /app /setup

    cat << 'EOF' > /setup/generate_video.py
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont
import csv
import math
import os

os.makedirs('/app', exist_ok=True)
video_path = '/app/sensor_feed.mp4'
truth_csv_path = '/app/truth.csv'

fps = 1
duration = 60
width, height = 640, 480

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter(video_path, fourcc, fps, (width, height))

truth_data = []

# Base time: 2024-05-01T12:00:00Z
for i in range(duration):
    time_str = f"2024-05-01T12:00:{i:02d}Z"
    # Pressure formula: 100 + 10 * sin(t/5)
    pressure = 100.0 + 10.0 * math.sin(i / 5.0)

    truth_data.append({'timestamp': time_str, 'pressure': round(pressure, 1)})

    img = Image.new('RGB', (width, height), color=(0, 0, 0))
    d = ImageDraw.Draw(img)

    # Introduce glitches on specific frames (e.g., every 7th frame)
    if i % 7 == 0:
        d.text((50, 200), "S@STEM ERR0R", fill=(255, 0, 0))
    else:
        d.text((50, 100), "SYSTEM MONITOR v1.0", fill=(255, 255, 255))
        d.text((50, 150), f"Timestamp: {time_str}", fill=(255, 255, 255))
        d.text((50, 200), f"Pressure: {pressure:.1f} kPa", fill=(255, 255, 255))

    frame = cv2.cvtColor(np.array(img), cv2.COLOR_RGB2BGR)
    out.write(frame)

out.release()

with open(truth_csv_path, 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['timestamp', 'pressure'])
    writer.writeheader()
    writer.writerows(truth_data)
EOF

    python3 /setup/generate_video.py

    cat << 'EOF' > /setup/verifier.py
import pandas as pd
import numpy as np
import sys
import os

if not os.path.exists('/home/user/interpolated_pressure.csv'):
    print("MSE: 9999.0")
    sys.exit(1)

try:
    truth = pd.read_csv('/app/truth.csv')
    pred = pd.read_csv('/home/user/interpolated_pressure.csv')

    merged = pd.merge(truth, pred, on='timestamp', suffixes=('_true', '_pred'), how='inner')
    if len(merged) < 50: # Ensure they extracted most of the timeline
        print("MSE: 9999.0")
        sys.exit(1)

    mse = np.mean((merged['pressure_true'] - merged['pressure_pred'])**2)
    print(f"MSE: {mse}")
except Exception as e:
    print("MSE: 9999.0")
    sys.exit(1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
