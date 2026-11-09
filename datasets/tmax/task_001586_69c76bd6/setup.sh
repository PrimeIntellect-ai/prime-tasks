#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate corpora and dummy video
    python3 -c '
import os
import json
import random

# Generate clean corpus
for i in range(1, 51):
    data = [random.uniform(-100, 100) for _ in range(64)]
    with open(f"/app/corpus/clean/clean_{i:02d}.json", "w") as f:
        json.dump(data, f)

# Generate evil corpus
for i in range(1, 51):
    data = [random.uniform(-100, 100) for _ in range(64)]
    # Inject evil values
    data[10] = 1e-310
    data[20] = float("inf")
    data[30] = float("nan")
    # write manually to handle nan/inf as strings or let json handle it (json allows NaN/Infinity)
    with open(f"/app/corpus/evil/evil_{i:02d}.json", "w") as f:
        json.dump(data, f)

# Create a dummy video file
with open("/app/exfiltration_capture.mp4", "wb") as f:
    f.write(b"dummy video content")

# Create buggy extract script
with open("/app/extract_telemetry.py", "w") as f:
    f.write("""import json
import sys

def extract(video_path):
    # Buggy extraction
    pass

if __name__ == "__main__":
    extract(sys.argv[1])
""")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
