#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest Pillow cryptography

    mkdir -p /app /hidden /tmp/frames

    cat << 'EOF' > /tmp/setup.py
import os
import json
import subprocess
from PIL import Image
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding

# 1. Generate key and video
key = os.urandom(16)
key_bits = ''.join(f'{byte:08b}' for byte in key)

for i, bit in enumerate(key_bits):
    color = 255 if bit == '1' else 0
    img = Image.new('L', (100, 100), color=color)
    img.save(f'/tmp/frames/frame_{i:03d}.png')

subprocess.run([
    'ffmpeg', '-y', '-f', 'image2', '-framerate', '10',
    '-i', '/tmp/frames/frame_%03d.png',
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '/app/intercepted.mp4'
], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

# 2. Create and encrypt traffic.log
log_data = [
    {"request_id": "req_001", "method": "GET", "path": "/index.html", "headers": {"Cookie": "session_data=YWRtaW49ZmFsc2U="}},
    {"request_id": "req_002", "method": "GET", "path": "/api/data?file=..%2f..%2fetc%2fpasswd", "headers": {}},
]

log_text = "\n".join(json.dumps(r) for r in log_data).encode()
padder = padding.PKCS7(128).padder()
padded_data = padder.update(log_text) + padder.finalize()
cipher = Cipher(algorithms.AES(key), modes.ECB())
encryptor = cipher.encryptor()
enc_data = encryptor.update(padded_data) + encryptor.finalize()

with open('/app/traffic.log.enc', 'wb') as f:
    f.write(enc_data)

# 3. Create hidden test log
hidden_log = [
    {"request_id": "req_100", "method": "GET", "path": "/index.html", "headers": {"Cookie": "session_data=YWRtaW49ZmFsc2U="}},
    {"request_id": "req_102", "method": "GET", "path": "/index.html", "headers": {"Cookie": "session_data=c29tZXRoaW5nO2FkbWluPXRydWU="}}, 
    {"request_id": "req_105", "method": "GET", "path": "/api/data?file=..%2f..%2fetc%2fpasswd", "headers": {}}, 
    {"request_id": "req_110", "method": "GET", "path": "/index.html", "headers": {"X-Forwarded-For": "192.168.1.1; ls"}}, 
    {"request_id": "req_111", "method": "GET", "path": "/index.html", "headers": {"X-Forwarded-For": "192.168.1.1| ls"}}, 
    {"request_id": "req_119", "method": "GET", "path": "/index.html", "headers": {"X-Forwarded-For": "192.168.1.1$ls"}}, 
    {"request_id": "req_120", "method": "GET", "path": "/api/data?file=..%2F..%2Fetc%2Fpasswd", "headers": {}}, 
    {"request_id": "req_135", "method": "GET", "path": "/api/data?file=..%2f", "headers": {}}, 
    {"request_id": "req_142", "method": "GET", "path": "/index.html", "headers": {"Cookie": "session_data=YWRtaW49dHJ1ZQ=="}}, 
]
with open('/hidden/test_log.json', 'w') as f:
    f.write("\n".join(json.dumps(r) for r in hidden_log))
EOF

    python3 /tmp/setup.py
    rm -rf /tmp/setup.py /tmp/frames

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app /hidden
