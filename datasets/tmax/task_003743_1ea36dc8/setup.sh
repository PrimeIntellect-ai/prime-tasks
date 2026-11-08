#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest opencv-python-headless numpy

    mkdir -p /app

    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np
import os

regex_str = r"^\[(?P<ts>.*?)\] (?P<job>[A-Z0-9]+): (?P<data>.*)$"
fps = 10
width, height = 64, 64

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/pattern_source.mp4', fourcc, fps, (width, height), isColor=False)

for char in regex_str:
    val = ord(char)
    frame = np.full((height, width), val, dtype=np.uint8)
    out.write(frame)

out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    cat << 'EOF' > /app/oracle_process_logs.py
#!/usr/bin/env python3
import sys
import re
import hashlib

regex = re.compile(r"^\[(?P<ts>.*?)\] (?P<job>[A-Z0-9]+): (?P<data>.*)$")
seen = {}

for line in sys.stdin:
    match = regex.match(line.rstrip('\n'))
    if match:
        job = match.group('job')
        data = match.group('data')

        # Normalize
        norm_data = re.sub(r'\s+', ' ', data).strip().lower()

        # Hash
        md5_hash = hashlib.md5(norm_data.encode('utf-8')).hexdigest()

        if job not in seen:
            seen[job] = set()

        if md5_hash not in seen[job]:
            seen[job].add(md5_hash)
            print(f"{job}\t{norm_data}\t{md5_hash}")
EOF
    chmod +x /app/oracle_process_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
