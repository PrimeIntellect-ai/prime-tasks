#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scikit-learn opencv-python-headless fastapi uvicorn requests flask

    mkdir -p /app
    cat << 'EOF' > /app/setup.py
import cv2
import numpy as np
import pandas as pd
import os

# Generate video
out = cv2.VideoWriter('/app/experiment.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (640, 480))
for i in range(300):
    frame = np.ones((480, 640, 3), dtype=np.uint8) * (i % 255)
    out.write(frame)
out.release()

# Generate targets
np.random.seed(42)
targets = np.random.randn(300) * 5 + 50
df = pd.DataFrame({'frame_index': range(300), 'target_value': targets})
df.to_csv('/app/targets.csv', index=False)
EOF
    python3 /app/setup.py
    rm /app/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
