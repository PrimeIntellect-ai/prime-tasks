#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest numpy opencv-python-headless pandas

    mkdir -p /app

    python3 -c "
import cv2
import numpy as np
import csv

# Generate Video
fps = 10
duration = 60
out = cv2.VideoWriter('/app/machine_feed.mp4', cv2.VideoWriter_fourcc(*'mp4v'), fps, (200, 200))
np.random.seed(42)

for sec in range(duration):
    base_intensity = 100 if sec % 10 < 5 else 180  # Step function to create changepoints
    for frame in range(fps):
        img = np.zeros((200, 200, 3), dtype=np.uint8)
        noise = np.random.normal(0, 5, (50, 50))
        region = np.clip(base_intensity + noise, 0, 255).astype(np.uint8)
        img[0:50, 0:50, :] = np.stack((region,)*3, axis=-1)
        out.write(img)
out.release()

# Generate CSV
with open('/app/machine_logs.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['Second', 'Operator', 'Notes'])
    for sec in range(duration):
        if sec == 12 or sec == 45:
            writer.writerow([sec, 'Alice', f'Checked machine.\nEverything OK at sec {sec}.'])
        else:
            writer.writerow([sec, 'Bob', 'Routine check.'])
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
