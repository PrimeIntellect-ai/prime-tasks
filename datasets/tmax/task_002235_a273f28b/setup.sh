#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr
    pip3 install pytest opencv-python-headless cryptography pytesseract Pillow numpy

    # Create directories
    mkdir -p /app
    useradd -m -s /bin/bash user || true

    # Generate the surveillance video with the hidden encrypted token
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np
import base64
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding

key = b'0123456789abcdef0123456789abcdef'
iv = b'abcdef9876543210'
plaintext = b'SUPER_SECRET_PENTEST_TOKEN_99'

padder = padding.PKCS7(128).padder()
padded_data = padder.update(plaintext) + padder.finalize()

cipher = Cipher(algorithms.AES(key), modes.CBC(iv))
encryptor = cipher.encryptor()
ciphertext = encryptor.update(padded_data) + encryptor.finalize()

encoded_token = base64.b64encode(ciphertext).decode('utf-8')

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/surveillance_capture.mp4', fourcc, 30.0, (640, 480))

for i in range(200):
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    if 120 <= i <= 150:
        cv2.putText(frame, encoded_token, (10, 240), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1, cv2.LINE_AA)
    out.write(frame)

out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    # Create the decryptor script template
    cat << 'EOF' > /home/user/decryptor.py
# AES Key: b'0123456789abcdef0123456789abcdef'
# IV: b'abcdef9876543210'
# TODO: Implement decryption using cryptography.hazmat
EOF

    # Set permissions
    chmod -R 777 /home/user
    chmod -R 777 /app
