#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest opencv-python-headless pandas numpy scikit-learn

    mkdir -p /app
    useradd -m -s /bin/bash user || true

    python3 -c "
import cv2
import numpy as np
import pandas as pd

# Video settings
fps = 1
duration = 120
width, height = 100, 100

out = cv2.VideoWriter('/app/reaction_experiment.mp4', cv2.VideoWriter_fourcc(*'mp4v'), fps, (width, height))
np.random.seed(42)

train_data = []
test_data = []
truth_data = []

for i in range(duration):
    # Base color changes over time (increasing redness)
    r = int(100 + i + np.random.normal(0, 5))
    r = max(0, min(255, r))

    # Create frame: B=50, G=50, R=r
    frame = np.full((height, width, 3), (50, 50, r), dtype=np.uint8)
    out.write(frame)

    # Tabular features
    temp = 20.0 + i * 0.5 + np.random.normal(0, 1)
    cat = 1 if i > 50 else 0

    # Underlying true yield relationship
    yield_val = (r * 0.3) + (temp * 0.5) + (cat * 10) + np.random.normal(0, 2.0)

    if i < 80:
        train_data.append([i, temp, cat, yield_val])
    else:
        test_data.append([i, temp, cat])
        truth_data.append([i, yield_val])

out.release()

# Save datasets
pd.DataFrame(train_data, columns=['time_sec', 'temperature', 'catalyst', 'reaction_yield']).to_csv('/home/user/train_log.csv', index=False)
pd.DataFrame(test_data, columns=['time_sec', 'temperature', 'catalyst']).to_csv('/home/user/test_log.csv', index=False)
pd.DataFrame(truth_data, columns=['time_sec', 'reaction_yield']).to_csv('/app/hidden_truth.csv', index=False)
"

    chmod 777 /app/reaction_experiment.mp4
    chmod 777 /app/hidden_truth.csv
    chmod -R 777 /home/user
