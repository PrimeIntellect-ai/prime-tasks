#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libglib2.0-0
    pip3 install pytest opencv-python-headless numpy pandas scikit-learn

    mkdir -p /app /truth

    cat << 'EOF' > /setup.py
import cv2
import numpy as np
import pandas as pd
import os

os.makedirs('/app', exist_ok=True)
os.makedirs('/truth', exist_ok=True)

fps = 30
duration = 10
total_frames = fps * duration

# Ground truth base signal: sine wave
frames = np.arange(total_frames)
base_signal = 100 + 50 * np.sin(2 * np.pi * frames / 150)

# Create raw signal with anomalies
raw_signal = base_signal.copy()
anomalies = {
    45: 255,   # Flash
    46: 255,   # Flash
    120: 0,    # Drop
    200: 250,  # Flash
    280: 5     # Drop
}
for f, val in anomalies.items():
    raw_signal[f] = val

# Save video
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/sensor_feed.mp4', fourcc, fps, (100, 100), False)

for val in raw_signal:
    frame = np.full((100, 100), fill_value=int(val), dtype=np.uint8)
    out.write(frame)
out.release()

# Save ground truth reference
df_truth = pd.DataFrame({'frame': frames, 'value': base_signal})
df_truth.to_csv('/truth/reference.csv', index=False)
EOF

    python3 /setup.py
    rm /setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
