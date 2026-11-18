#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app/corpus/evil /app/corpus/clean

    cat << 'EOF' > /tmp/generate_video.py
import cv2
import numpy as np

secret = "X_BYPASS"
binary_string = ''.join(format(ord(c), '08b') for c in secret)

out = cv2.VideoWriter('/app/incident.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 1, (200, 200))
for bit in binary_string:
    frame = np.zeros((200, 200, 3), dtype=np.uint8)
    if bit == '1':
        frame[0:50, 0:50] = (255, 255, 255)
    out.write(frame)
out.release()
EOF
    python3 /tmp/generate_video.py

    echo -n "../../../etc/shadow" > /app/corpus/evil/evil_1.txt
    echo -n "images/..%2f..%2fpasswd" > /app/corpus/evil/evil_2.txt
    echo -n "X_BYPASS_malware.exe" > /app/corpus/evil/evil_3.txt
    echo -n "/var/www/html/shell.php" > /app/corpus/evil/evil_4.txt
    echo -n "legit.png%00.php" > /app/corpus/evil/evil_5.txt

    echo -n "user_avatar.jpg" > /app/corpus/clean/clean_1.txt
    echo -n "documents/january_report.pdf" > /app/corpus/clean/clean_2.txt
    echo -n "data_backup.tar.gz" > /app/corpus/clean/clean_3.txt
    echo -n "scripts/main.js" > /app/corpus/clean/clean_4.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
