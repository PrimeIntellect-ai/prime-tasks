#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest opencv-python-headless numpy matplotlib flask fastapi uvicorn requests

    useradd -m -s /bin/bash user || true
    mkdir -p /app
    touch /app/experiment_feed.mp4

    cat << 'EOF' > /home/user/analyze.py
import cv2
import numpy as np
import json
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

def extract_and_analyze(video_path):
    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    frame_interval = int(fps) # 1 frame per second

    intensities = []
    count = 0
    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
        if count % frame_interval == 0:
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            intensities.append(np.mean(gray))
        count += 1
    cap.release()

    intensities = np.array(intensities)

    # Bootstrap
    np.random.seed(42)
    n_iterations = 1000
    n_size = len(intensities)
    means = []
    for _ in range(n_iterations):
        sample = np.random.choice(intensities, size=n_size, replace=True)
        means.append(np.mean(sample))

    means = np.array(means)
    lower = np.percentile(means, 2.5)
    upper = np.percentile(means, 97.5)

    res = {
        "mean": float(np.mean(intensities)),
        "lower_bound": float(lower),
        "upper_bound": float(upper)
    }

    with open('/home/user/tracking.json', 'w') as f:
        json.dump(res, f)

    # Buggy plot code: saving before plotting
    plt.figure()
    plt.savefig('/home/user/bootstrap_dist.png')
    plt.hist(means, bins=30, alpha=0.7)
    plt.title('Bootstrap Distribution')

if __name__ == "__main__":
    extract_and_analyze('/app/experiment_feed.mp4')
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
