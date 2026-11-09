#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-opencv tesseract-ocr
    pip3 install pytest pytesseract

    mkdir -p /app

    # Generate the video fixture
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

logs = [
    "System boot initiated",
    "Loading kernel modules",
    "Network interface eth0 up",
    "Starting sshd service",
    "User admin logged in from 192.168.1.50",
    "Disk space warning on /dev/sda1",
    "Database service starting",
    "Database connection established",
    "Worker thread 1 spawned",
    "Worker thread 2 spawned",
    "WARN: High CPU utilization detected",
    "Rate limit exceeded for endpoint /api/v1/data",
    "ERROR: Segmentation fault in worker thread 1",
    "Attempting to restart worker thread 1",
    "FATAL: Memory corruption detected",
    "Initiating emergency shutdown",
    "Flushing disk buffers",
    "Stopping sshd service",
    "Network interface eth0 down",
    "System halted"
]

out = cv2.VideoWriter('/app/incident_044.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 2, (640, 480))
font = cv2.FONT_HERSHEY_SIMPLEX
for i in range(len(logs)):
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    y0, dy = 30, 30
    for j, line in enumerate(logs[max(0, i-15):i+1]):
        y = y0 + j*dy
        cv2.putText(frame, f"2024-10-12T08:33:{i:02d}Z INFO {line}", (10, y), font, 0.5, (255, 255, 255), 1, cv2.LINE_AA)
    out.write(frame)
out.release()
EOF
    python3 /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
