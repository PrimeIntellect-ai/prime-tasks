#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg golang-go
    pip3 install pytest

    mkdir -p /app/raw_data
    ffmpeg -f lavfi -i testsrc=duration=16:size=320x240:rate=30 -c:v libx264 /app/reference.mp4

    cat << 'EOF' > /tmp/generate.py
import os
import random

os.makedirs('/app/raw_data', exist_ok=True)
headers = [b'HEADER_A_1234567', b'HEADER_B_9876543', b'HEADER_C_0000000'] # 16 bytes each

# Create 100 unique payloads
unique_payloads = [os.urandom(1024 * 50) for _ in range(100)] # 50 KB each

file_count = 0
for i in range(2000): # 2000 files
    header = random.choice(headers)
    payload = random.choice(unique_payloads)
    content = header + payload
    path = f'/app/raw_data/file_{file_count}.bin'
    with open(path, 'wb') as f:
        f.write(content)
    file_count += 1
EOF
    python3 /tmp/generate.py
    rm /tmp/generate.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
