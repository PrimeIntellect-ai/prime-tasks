#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        libzbar0 \
        libgl1 \
        libglib2.0-0

    pip3 install pytest qrcode Pillow opencv-python-headless pyzbar

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /tmp/generate_assets.py
import os
import json
import cv2
import qrcode
import numpy as np

# 1. Generate Video
token = "SECURE_TOKEN_v9_88291a"
qr = qrcode.QRCode(version=1, box_size=10, border=5)
qr.add_data(token)
qr.make(fit=True)
img = qr.make_image(fill_color="black", back_color="white").convert('RGB')
qr_frame = np.array(img)[:, :, ::-1] # RGB to BGR for cv2

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/rotation_alert.mp4', fourcc, 1.0, (qr_frame.shape[1], qr_frame.shape[0]))

blank_frame = np.zeros_like(qr_frame)
blank_frame.fill(255)

for i in range(10):
    if i == 5:
        out.write(qr_frame)
    else:
        out.write(blank_frame)

out.release()

# 2. Generate Corpus
clean1 = {
    "method": "POST",
    "headers": {"Authorization": f"Bearer {token}"},
    "cookies": {}
}
clean2 = {
    "method": "POST",
    "headers": {"X-Encoded-Payload": "SGVsbG8gV29ybGQ="},
    "cookies": {"session_id": token}
}

evil1 = {
    "method": "POST",
    "headers": {"Authorization": "Bearer SECURE_TOKEN_v8_old"},
    "cookies": {}
}
evil2 = {
    "method": "POST",
    "headers": {
        "Authorization": f"Bearer {token}",
        "X-Encoded-Payload": "PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg=="
    },
    "cookies": {}
}
evil3 = {
    "method": "POST",
    "headers": {
        "Authorization": f"Bearer {token}",
        "X-Encoded-Payload": "U0VMRUNUICogRlJPTSB1c2VycyBXSEVSRSAxPTE="
    },
    "cookies": {}
}
evil4 = {
    "method": "POST",
    "headers": {},
    "cookies": {}
}

def write_json(path, data):
    with open(path, 'w') as f:
        json.dump(data, f)

write_json("/app/corpus/clean/clean1.json", clean1)
write_json("/app/corpus/clean/clean2.json", clean2)
write_json("/app/corpus/evil/evil1.json", evil1)
write_json("/app/corpus/evil/evil2.json", evil2)
write_json("/app/corpus/evil/evil3.json", evil3)
write_json("/app/corpus/evil/evil4.json", evil4)
EOF

    python3 /tmp/generate_assets.py
    rm /tmp/generate_assets.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
