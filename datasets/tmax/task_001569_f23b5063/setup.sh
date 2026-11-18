#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr python3-opencv build-essential coreutils
    pip3 install pytest

    # Pre-computation / Setup Script for the environment:
    mkdir -p /app/storage_metadata/legacy /app/storage_metadata/active /home/user/dropzone

    # Create safe JSON files
    for i in $(seq 1 5); do
      dd if=/dev/urandom of=/app/storage_metadata/active/safe_$i.json bs=1K count=15 2>/dev/null
      echo '{"status": "secure", "data": "'$(base64 /app/storage_metadata/active/safe_$i.json | head -c 50)'"}' > /app/storage_metadata/active/safe_$i.json
    done

    # Create compromised JSON files (size > 10KB)
    dd if=/dev/urandom of=/app/storage_metadata/legacy/comp_1.json bs=1K count=12 2>/dev/null
    echo '{"id": 101, "status": "compromised", "padding": "'$(head -c 12000 < /dev/zero | tr '\0' 'x')'"}' > /app/storage_metadata/legacy/comp_1.json
    dd if=/dev/urandom of=/app/storage_metadata/active/comp_2.json bs=1K count=15 2>/dev/null
    echo '{"id": 102, "status": "compromised", "padding": "'$(head -c 15000 < /dev/zero | tr '\0' 'x')'"}' > /app/storage_metadata/active/comp_2.json

    # Create a small compromised JSON file (should NOT be matched because size < 10KB)
    echo '{"id": 103, "status": "compromised"}' > /app/storage_metadata/legacy/comp_small.json

    # Create tarball fixtures for the verifier
    mkdir -p /app/tar_test_dir
    touch /app/tar_test_dir/file1.txt
    touch /app/tar_test_dir/file2.log
    tar -cf /app/test_safe.tar -C /app/tar_test_dir file1.txt file2.log

    # Create a malicious tarball manually (zip slip) using python
    python3 -c '
import tarfile
with tarfile.open("/app/test_malicious.tar", "w") as tar:
    ti = tarfile.TarInfo(name="../etc/passwd")
    ti.size = 0
    tar.addfile(ti)
'

    # Generate the video fixture
    python3 -c '
import cv2
import numpy as np
import os
os.makedirs("/app", exist_ok=True)
out = cv2.VideoWriter("/app/console_recording.mp4", cv2.VideoWriter_fourcc(*"mp4v"), 30, (640, 480))
breach_frames = [30, 45, 90, 150, 210, 300, 350, 400, 500, 600, 700, 850, 1000, 1200]
for i in range(1800):
    img = np.zeros((480, 640, 3), dtype=np.uint8)
    if i in breach_frames:
        cv2.putText(img, "BREACH_DETECTED", (50, 240), cv2.FONT_HERSHEY_SIMPLEX, 2, (255, 255, 255), 3)
    else:
        cv2.putText(img, f"SYSTEM_NORMAL {i}", (50, 240), cv2.FONT_HERSHEY_SIMPLEX, 2, (0, 255, 0), 3)
    out.write(img)
out.release()
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
