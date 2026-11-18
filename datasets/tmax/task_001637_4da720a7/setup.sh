#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        curl \
        libgl1 \
        libglib2.0-0 \
        cargo \
        rustc \
        ffmpeg

    pip3 install pytest numpy pandas opencv-python

    mkdir -p /app/corpus/clean \
             /app/corpus/evil \
             /app/hidden_corpus/clean \
             /app/hidden_corpus/evil

    cat << 'EOF' > /tmp/setup.py
import cv2
import numpy as np
import pandas as pd
import os

# 1. Create Video
out = cv2.VideoWriter('/app/dashcam.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10.0, (100, 100), isColor=False)
for i in range(50):
    img = np.full((100, 100), 50 if i != 25 else 245, dtype=np.uint8)
    out.write(cv2.cvtColor(img, cv2.COLOR_GRAY2BGR))
out.release()

# 2. Create telemetry_base.csv
timestamps = np.arange(0.0, 5.0, 0.1)
speed = 20.0 + np.sin(timestamps)
speed[12] = np.nan # 1.2s
speed[34] = np.nan # 3.4s
df_base = pd.DataFrame({'timestamp': timestamps, 'speed': speed, 'steering': np.random.normal(0, 1, 50)})
df_base.to_csv('/app/telemetry_base.csv', index=False)

# 3. Create Corpora (Clean vs Evil)
def generate_corpus(path, is_evil):
    for i in range(20):
        raw_sensor = np.random.normal(100, 15, 100)
        if is_evil:
            # Global standard scaling (Leaky)
            sensor_scaled = (raw_sensor - np.mean(raw_sensor)) / np.std(raw_sensor)
        else:
            # Rolling standard scaling (Causal)
            sensor_scaled = []
            for j in range(len(raw_sensor)):
                if j < 2:
                    sensor_scaled.append(0.0)
                else:
                    window = raw_sensor[:j]
                    sensor_scaled.append((raw_sensor[j] - np.mean(window)) / (np.std(window) + 1e-5))

        df = pd.DataFrame({'raw_sensor': raw_sensor, 'sensor_scaled': sensor_scaled})
        df.to_csv(f"{path}/file_{i}.csv", index=False)

generate_corpus("/app/corpus/clean", False)
generate_corpus("/app/corpus/evil", True)
generate_corpus("/app/hidden_corpus/clean", False)
generate_corpus("/app/hidden_corpus/evil", True)
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
