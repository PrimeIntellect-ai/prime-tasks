#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest opencv-python-headless scikit-image

    # Create dummy video
    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=40:size=640x480:rate=30 -c:v libx264 /app/experiment.mp4

    # Generate metadata
    mkdir -p /home/user/raw_metadata
    cat << 'EOF' > /tmp/setup_metadata.py
import os
import json
import random

os.makedirs("/home/user/raw_metadata", exist_ok=True)
for frame_idx in range(0, 1001, 25):
    sub_dir = f"/home/user/raw_metadata/folder_{random.randint(1, 10)}"
    os.makedirs(sub_dir, exist_ok=True)
    file_path = os.path.join(sub_dir, f"meta_data_{random.randint(1000, 9999)}.json")
    with open(file_path, "w") as f:
        json.dump({"target_frame": frame_idx, "experiment_id": "alpha_1"}, f)
EOF
    python3 /tmp/setup_metadata.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
