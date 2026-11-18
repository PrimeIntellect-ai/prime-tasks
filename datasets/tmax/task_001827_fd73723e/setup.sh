#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg build-essential
    pip3 install pytest

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create dummy video with 30 frames
    ffmpeg -f lavfi -i color=c=blue:s=320x240:d=1 -frames:v 30 /app/network_capture.mp4

    # Create extract_edges.py
    cat << 'EOF' > /app/extract_edges.py
#!/usr/bin/env python3
import sys
print("Source,Target")
print("0,1")
print("0,2")
print("0,3")
print("0,4")
print("1,2")
print("1,3")
print("1,4")
print("2,3")
print("2,4")
print("3,4")
EOF
    chmod +x /app/extract_edges.py

    # Generate corpora
    python3 -c '
import os
import random

clean_dir = "/app/corpora/clean"
evil_dir = "/app/corpora/evil"

for i in range(20):
    max_deg = random.randint(2, 6)
    with open(f"{clean_dir}/graph_{i}.csv", "w") as f:
        f.write("Source,Target\n")
        for j in range(1, max_deg + 1):
            f.write(f"0,{j}\n")

for i in range(20):
    max_deg = random.randint(7, 15)
    with open(f"{evil_dir}/graph_{i}.csv", "w") as f:
        f.write("Source,Target\n")
        for j in range(1, max_deg + 1):
            f.write(f"0,{j}\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
