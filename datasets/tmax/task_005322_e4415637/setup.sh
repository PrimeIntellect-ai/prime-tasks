#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libglib2.0-0
    pip3 install pytest opencv-python-headless numpy pandas

    mkdir -p /app
    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_video.py
import cv2
import numpy as np
import math

width, height = 640, 480
fps = 30
duration = 10
num_frames = fps * duration

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/tracking.mp4', fourcc, fps, (width, height), isColor=False)

with open('/tmp/ground_truth.csv', 'w') as f:
    f.write("frame_id,x,y\n")
    for i in range(num_frames):
        img = np.zeros((height, width), dtype=np.uint8)
        x = int(width / 2 + 200 * math.cos(i * 0.1))
        y = int(height / 2 + 150 * math.sin(i * 0.15))
        cv2.circle(img, (x, y), 5, 255, -1)
        out.write(img)
        f.write(f"{i},{x},{y}\n")

out.release()
EOF
    python3 /tmp/generate_video.py

    cat << 'EOF' > /home/user/etl.sql
-- Broken ETL script with implicit cross join
SELECT 
  p1.frame_id,
  SQRT((p1.x - p2.x)*(p1.x - p2.x) + (p1.y - p2.y)*(p1.y - p2.y)) as distance
FROM positions p1, positions p2
-- Missing proper moving average logic and filtering
EOF

    cat << 'EOF' > /tmp/solve.py
import pandas as pd
import numpy as np

df = pd.read_csv('/tmp/ground_truth.csv')
df['prev_x'] = df['x'].shift(1)
df['prev_y'] = df['y'].shift(1)
df['distance'] = np.sqrt((df['x'] - df['prev_x'])**2 + (df['y'] - df['prev_y'])**2)
df['distance'] = df['distance'].fillna(0)
df['moving_avg_distance'] = df['distance'].rolling(window=5, min_periods=1).mean()
df[['frame_id', 'distance', 'moving_avg_distance']].to_csv('/tmp/reference_speeds.csv', index=False)
EOF
    python3 /tmp/solve.py

    cat << 'EOF' > /tmp/verifier.py
import pandas as pd
import sys

try:
    ref = pd.read_csv('/tmp/reference_speeds.csv')
    agent = pd.read_csv('/home/user/smoothed_speeds.csv')

    # Align by frame_id
    merged = pd.merge(ref, agent, on='frame_id', suffixes=('_ref', '_agent'))
    if len(merged) == 0:
        print("MSE: 9999.0")
        sys.exit(1)

    mse = ((merged['moving_avg_distance_ref'] - merged['moving_avg_distance_agent'])**2).mean()
    print(f"MSE: {mse}")
    if mse <= 0.5:
        sys.exit(0)
    else:
        sys.exit(1)
except Exception as e:
    print(f"MSE: 9999.0")
    sys.exit(1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app /tmp/ground_truth.csv /tmp/reference_speeds.csv /tmp/verifier.py
