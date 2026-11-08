#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create dummy video file
    mkdir -p /app
    touch /app/test_video.mp4

    # Create the buggy script
    mkdir -p /home/user
    cat << 'EOF' > /home/user/video_processor.py
import sys
import json

def get_timestamps(duration, fps):
    timestamps = []
    # Buggy recursive function to get timestamps
    def _add_ts(current):
        if current >= duration:
            return
        timestamps.append(current)
        # Bug: Float accumulation drift and recursion limit issue
        _add_ts(current + 1.0/fps)

    sys.setrecursionlimit(100) # Artificially low to trigger build failure
    _add_ts(0.0)
    return timestamps

def main():
    video_path = "/app/test_video.mp4"
    duration = 5.0
    fps = 30

    ts = get_timestamps(duration, fps)

    with open("/home/user/fixed_timestamps.json", "w") as f:
        json.dump(ts, f)

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
