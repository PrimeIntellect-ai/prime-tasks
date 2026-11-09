#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest numpy opencv-python-headless pandas

    mkdir -p /app

    cat << 'EOF' > /tmp/generate_signal.py
import numpy as np
import cv2
import csv

# 60 seconds of data
duration = 60
fps = 30
total_frames = duration * fps
time_sec = np.linspace(0, duration, total_frames)

# Underlying signal: sine wave + random noise + a few distinct peaks
signal = (np.sin(time_sec * 0.5) + 1) / 2
signal += np.random.normal(0, 0.05, total_frames)
signal[300:330] = 2.0  # Spike 1 at 10s
signal[1200:1230] = 2.5 # Spike 2 at 40s

# Normalize signal to 0-255 for video
video_signal = np.clip(signal / max(signal) * 255, 0, 255).astype(np.uint8)

# Create video
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/experiment.mp4', fourcc, fps, (100, 100))

for val in video_signal:
    frame = np.full((100, 100, 3), val, dtype=np.uint8)
    out.write(frame)
out.release()

# Generate Sensor CSV
# The sensor starts at 1700000000, but the video actually started at 1700000007 (7 seconds late)
video_true_start = 1700000007

with open('/app/sensor.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp_ms', 'luminosity_raw'])

    # Generate irregular sensor samples around the true signal time
    for i in range(duration * 10): # 10Hz avg sensor
        t_offset = i * 0.1 + np.random.uniform(-0.02, 0.02)
        if t_offset >= duration: break

        # Sensor timestamps
        ts_ms = int((video_true_start + t_offset) * 1000)

        # Interpolate underlying signal for sensor
        idx = int(t_offset * fps)
        if idx >= total_frames: idx = total_frames - 1

        # Sensor has a different scale and offset
        sensor_val = (signal[idx] * 450) + 120 + np.random.normal(0, 10)
        writer.writerow([ts_ms, round(sensor_val, 2)])
EOF

    python3 /tmp/generate_signal.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
