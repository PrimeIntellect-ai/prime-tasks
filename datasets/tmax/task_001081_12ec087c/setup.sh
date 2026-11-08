#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libglib2.0-0 libsm6 libxext6 libxrender-dev ffmpeg
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app/corpus/evil /app/corpus/clean

    cat << 'EOF' > /tmp/setup.py
import os
import cv2
import numpy as np
import base64
import random
import string

key_hex = "5f4dcc3b5aa765d61d8327deb882cf992b95990a9151374a29a28cd1ce8a4128"
key_bytes = bytes.fromhex(key_hex)

# Generate Video
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/capture.mp4', fourcc, 1.0, (640, 480))

for i in range(256):
    byte_idx = i // 8
    bit_idx = 7 - (i % 8)
    bit = (key_bytes[byte_idx] >> bit_idx) & 1

    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    if bit == 1:
        frame[240, 320, 2] = 255  # Red channel > 128
    else:
        frame[240, 320, 2] = 0

    out.write(frame)
out.release()

# Generate Corpora
def xor_crypt(data, key):
    return bytes([data[i] ^ key[i % len(key)] for i in range(len(data))])

def get_random_chars(length):
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=length))

for i in range(50):
    # Evil payload
    evil_text = f"Data {get_random_chars(10)} EXFIL-{get_random_chars(4)} end".encode()
    evil_enc = base64.b64encode(xor_crypt(evil_text, key_bytes)).decode()
    with open(f'/app/corpus/evil/payload_{i}.txt', 'w') as f:
        f.write(evil_enc)

    # Clean payload
    clean_text = f"Data {get_random_chars(10)} CLEAN-{get_random_chars(4)} end".encode()
    clean_enc = base64.b64encode(xor_crypt(clean_text, key_bytes)).decode()
    with open(f'/app/corpus/clean/payload_{i}.txt', 'w') as f:
        f.write(clean_enc)

EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
