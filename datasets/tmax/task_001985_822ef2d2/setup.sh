#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libglib2.0-0
    pip3 install pytest numpy pandas opencv-python-headless

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil
    mkdir -p /app/sensor_logs

    cat << 'EOF' > /tmp/generate_data.py
import os
import numpy as np
import pandas as pd
import cv2
import random
import shutil

# Generate drone_feed.mp4
fps = 30
duration = 10
total_frames = fps * duration
width, height = 320, 240

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/drone_feed.mp4', fourcc, fps, (width, height), isColor=False)

black_frames = {15, 45, 90, 150, 200, 250}

for i in range(total_frames):
    if i in black_frames:
        frame = np.zeros((height, width), dtype=np.uint8)
    else:
        val = int(128 + 100 * np.sin(i * 2 * np.pi / total_frames))
        frame = np.full((height, width), val, dtype=np.uint8)
    out.write(frame)

out.release()

# Generate corpora
def generate_clean(idx):
    timestamps = np.arange(0, 10, 1.0/30)
    readings = 50 + 20 * np.sin(timestamps * 2 * np.pi / 2.0) + np.random.normal(0, 1, len(timestamps))
    df = pd.DataFrame({'timestamp': timestamps, 'sensor_reading': readings})
    drop_indices = np.random.choice(df.index, size=int(0.02 * len(df)), replace=False)
    df.loc[drop_indices, 'sensor_reading'] = np.nan
    df.to_csv(f'/app/corpora/clean/clean_{idx}.csv', index=False)
    return f'/app/corpora/clean/clean_{idx}.csv'

def generate_evil(idx, anomaly_type):
    timestamps = np.arange(0, 10, 1.0/30)
    readings = 50 + 20 * np.sin(timestamps * 2 * np.pi / 2.0) + np.random.normal(0, 1, len(timestamps))
    df = pd.DataFrame({'timestamp': timestamps, 'sensor_reading': readings})

    if anomaly_type == 'jump':
        df.loc[100, 'sensor_reading'] += 60.0
    elif anomaly_type == 'negative':
        df.loc[150, 'sensor_reading'] = -10.0
    elif anomaly_type == 'missing':
        drop_indices = np.random.choice(df.index, size=int(0.1 * len(df)), replace=False)
        df.loc[drop_indices, 'sensor_reading'] = np.nan
    elif anomaly_type == 'string':
        df['sensor_reading'] = df['sensor_reading'].astype(object)
        df.loc[200, 'sensor_reading'] = 'error'

    df.to_csv(f'/app/corpora/evil/evil_{idx}.csv', index=False)
    return f'/app/corpora/evil/evil_{idx}.csv'

clean_files = []
evil_files = []

for i in range(20):
    clean_files.append(generate_clean(i))

anomaly_types = ['jump', 'negative', 'missing', 'string']
for i in range(20):
    evil_files.append(generate_evil(i, anomaly_types[i % 4]))

for f in clean_files + evil_files:
    shutil.copy(f, '/app/sensor_logs/')
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
