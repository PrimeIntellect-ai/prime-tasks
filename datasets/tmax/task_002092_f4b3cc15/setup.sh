#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip

    # Increase pip timeout and install required packages
    pip3 install --default-timeout=100 pytest cryptography opencv-python-headless numpy

    mkdir -p /app

    cat << 'EOF' > /tmp/setup_env.py
import cv2
import numpy as np
import os, json, hashlib
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend

# Generate video
out = cv2.VideoWriter('/app/security_cam.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (320, 240))
for i in range(300):
    frame = np.zeros((240, 320, 3), dtype=np.uint8)
    # 142 frames with red block
    if i < 142:
        frame[0:10, 0:10] = (0, 0, 255)  # OpenCV uses BGR
    out.write(frame)
out.release()

# Generate encrypted evidence
passphrase = b"PIN:142"
key = hashlib.sha256(passphrase).digest()
iv = os.urandom(16)

data = json.dumps({
    "auth_token": "8f9a2b4c6d8e0f1",
    "recovered_data": {
        "files_accessed": ["/etc/shadow", "/root/.bash_history"],
        "malware_family": "Lazarus"
    }
}).encode('utf-8')

# PKCS7 padding
pad_len = 16 - (len(data) % 16)
data += bytes([pad_len] * pad_len)

cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
encryptor = cipher.encryptor()
ciphertext = encryptor.update(data) + encryptor.finalize()

with open("/app/evidence.enc", "wb") as f:
    f.write(iv + ciphertext)
EOF

    python3 /tmp/setup_env.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
