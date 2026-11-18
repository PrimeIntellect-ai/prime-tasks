#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg sqlite3
    pip3 install pytest numpy pandas scikit-learn imageio imageio-ffmpeg opencv-python-headless

    mkdir -p /app/eval_corpus/clean
    mkdir -p /app/eval_corpus/evil

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import imageio
import os
import sqlite3
import random

# Generate video
fps = 30
duration = 10
num_frames = fps * duration
frames = []
for i in range(num_frames):
    if i % 10 == 0:
        frame = np.ones((100, 100, 3), dtype=np.uint8) * 255
    else:
        frame = np.zeros((100, 100, 3), dtype=np.uint8)
    frames.append(frame)

imageio.mimwrite('/app/calibration.mp4', frames, fps=fps)

# Generate DB and CSVs
conn = sqlite3.connect('/app/telemetry.db')
c = conn.cursor()
c.execute('CREATE TABLE sensor_data (timestamp REAL, sample_id TEXT, signal_2 REAL)')

for i in range(25):
    # Clean
    sample_id = f'clean_{i}'
    csv_path = f'/app/eval_corpus/clean/{sample_id}.csv'
    with open(csv_path, 'w') as f:
        f.write('timestamp,signal_1\n')
        for t in range(100):
            sig1 = random.uniform(0, 10)
            sig2 = 3.0 * sig1 + random.gauss(0, 0.01)
            f.write(f'{t},{sig1}\n')
            c.execute('INSERT INTO sensor_data VALUES (?, ?, ?)', (t, sample_id, sig2))

for i in range(25):
    # Evil
    sample_id = f'evil_{i}'
    csv_path = f'/app/eval_corpus/evil/{sample_id}.csv'
    slope = random.choice([1.5, 4.5, -3.0])
    with open(csv_path, 'w') as f:
        f.write('timestamp,signal_1\n')
        for t in range(100):
            sig1 = random.uniform(0, 10)
            sig2 = slope * sig1 + random.gauss(0, 0.01)
            f.write(f'{t},{sig1}\n')
            c.execute('INSERT INTO sensor_data VALUES (?, ?, ?)', (t, sample_id, sig2))

conn.commit()
conn.close()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
