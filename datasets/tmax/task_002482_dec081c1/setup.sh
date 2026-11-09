#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install system dependencies for OpenCV, ffmpeg, SSH, cron, and netcat
    apt-get install -y ffmpeg libsm6 libxext6 libgl1 openssh-server openssh-client cron netcat-openbsd sudo

    # Install Python dependencies
    pip3 install numpy opencv-python

    # Create user
    useradd -m -s /bin/bash user || true

    # Generate dummy video file
    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=60:size=640x480:rate=30 /app/server_monitor.mp4

    # Create legacy analyzer script
    cat << 'EOF' > /home/user/legacy_analyzer.py
import cv2
import numpy as np

def count_dark_frames(video_path):
    cap = cv2.VideoCapture(video_path)
    dark_count = 0
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        if np.mean(frame) < 100.0:
            dark_count += 1
    cap.release()
    return dark_count

if __name__ == "__main__":
    print(count_dark_frames("/app/server_monitor.mp4"))
EOF

    # Setup SSH for user
    mkdir -p /var/run/sshd
    mkdir -p /home/user/.ssh
    ssh-keygen -t rsa -N "" -f /home/user/.ssh/id_rsa
    cat /home/user/.ssh/id_rsa.pub > /home/user/.ssh/authorized_keys
    chmod 700 /home/user/.ssh
    chmod 600 /home/user/.ssh/authorized_keys
    chown -R user:user /home/user/.ssh

    # Ensure correct permissions
    chmod -R 777 /home/user
