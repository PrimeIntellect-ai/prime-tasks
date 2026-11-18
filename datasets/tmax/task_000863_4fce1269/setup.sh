#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libglib2.0-0
    pip3 install pytest numpy pandas opencv-python-headless

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import os
import numpy as np
import pandas as pd
import cv2

# Create directories
dirs = [
    "/app/holdout/clean",
    "/app/holdout/evil",
    "/home/user/data/training/clean",
    "/home/user/data/training/evil"
]
for d in dirs:
    os.makedirs(d, exist_ok=True)

# Generate baseline video
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/baseline_dash.mp4', fourcc, 1.0, (200, 200))
np.random.seed(42)
speed = np.linspace(50, 150, 30) + np.random.normal(0, 5, 30)
rpm = speed * 10 + np.random.normal(0, 50, 30)
for s, r in zip(speed, rpm):
    frame = np.zeros((200, 200, 3), dtype=np.uint8)
    s_h = int(min(max(s, 0), 200))
    r_h = int(min(max(r / 10, 0), 200))
    # Draw left bar (speed)
    cv2.rectangle(frame, (20, 200 - s_h), (80, 200), (255, 0, 0), -1)
    # Draw right bar (rpm)
    cv2.rectangle(frame, (120, 200 - r_h), (180, 200), (0, 0, 255), -1)
    out.write(frame)
out.release()

# Generate CSVs
def make_csv(path, is_evil):
    n = 100
    if not is_evil:
        # Correlated ~ 0.98
        s = np.random.normal(100, 20, n)
        r = s * 10 + np.random.normal(0, 20, n)
    else:
        # Less correlated ~ 0.30
        s = np.random.normal(100, 20, n)
        r = s * 3 + np.random.normal(1000, 200, n)

    df = pd.DataFrame({'Speed': s, 'RPM': r})
    if is_evil:
        # inject NaNs
        idx = np.random.choice(n, int(0.1 * n), replace=False)
        df.loc[idx, 'Speed'] = np.nan
        idx2 = np.random.choice(n, int(0.1 * n), replace=False)
        df.loc[idx2, 'RPM'] = np.nan
    df.to_csv(path, index=False)

for i in range(5):
    make_csv(f"/home/user/data/training/clean/log_{i}.csv", False)
    make_csv(f"/home/user/data/training/evil/log_{i}.csv", True)

for i in range(10):
    make_csv(f"/app/holdout/clean/log_{i}.csv", False)
    make_csv(f"/app/holdout/evil/log_{i}.csv", True)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
    chmod -R 777 /app
