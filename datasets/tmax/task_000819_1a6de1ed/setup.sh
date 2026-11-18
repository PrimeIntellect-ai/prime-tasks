#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app

    python3 -c '
import cv2
import numpy as np
import random
import os

os.makedirs("/app", exist_ok=True)
out = cv2.VideoWriter("/app/network_monitor.mp4", cv2.VideoWriter_fourcc(*"mp4v"), 30, (100, 100))
random.seed(42)
white_frames = random.sample(range(1200), 37)

for i in range(1200):
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    if i in white_frames:
        frame[50, 50] = [255, 255, 255]
    out.write(frame)
out.release()

with open("/app/crash.dmp", "wb") as f:
    f.write(os.urandom(20000))

with open("/app/crash.dmp", "r+b") as f:
    f.seek(9472)
    f.write(b"MODULO_83\x00")

buggy_code = """#!/usr/bin/env python3
import sys
arr = list(map(int, sys.argv[1].split(",")))
ans = 0
# Buggy boundary condition: misses the last comparison
for i in range(1, len(arr) - 1):
    diff = arr[i] - arr[i-1]
    if diff > 0:
        ans += diff
print(ans) # Buggy: missing modulo logic
"""
with open("/app/log_processor_buggy.py", "w") as f:
    f.write(buggy_code)

oracle_code = """#!/usr/bin/env python3
import sys
arr = list(map(int, sys.argv[1].split(",")))
ans = sum(max(0, arr[i] - arr[i-1]) for i in range(1, len(arr)))
print(ans % 83)
"""
with open("/app/oracle_processor", "w") as f:
    f.write(oracle_code)
os.chmod("/app/oracle_processor", 0o755)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
