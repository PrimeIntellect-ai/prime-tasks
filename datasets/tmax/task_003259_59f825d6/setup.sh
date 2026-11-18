#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest cryptography Pillow

    mkdir -p /app/frames
    mkdir -p /app/encrypted_corpora/evil
    mkdir -p /app/encrypted_corpora/clean
    mkdir -p /test_data/unencrypted_corpora/evil
    mkdir -p /test_data/unencrypted_corpora/clean

    cat << 'EOF' > /tmp/setup.py
import os
import hashlib
from PIL import Image, ImageDraw
import subprocess
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend

# 1. Generate Video and Extract Script
hashes = {}
texts = {
    12: "KEY_CHUNK: 4a2b9c11 | CHECKSUM: a2420489502b7dbd8e9df64de2719a71",
    25: "KEY_CHUNK: deadbeef | CHECKSUM: 00000000000000000000000000000000",
    38: "KEY_CHUNK: 8f7e6d5c | CHECKSUM: 934b53ebc83cdfa6fc39c8789311bd32",
    45: "KEY_CHUNK: 22334455 | CHECKSUM: e8dfd277715ec3da022dc70a16900ce2",
    49: "KEY_CHUNK: 66778899 | CHECKSUM: b7a10be69f201014e30485d452fb3e75"
}

for i in range(1, 51):
    img = Image.new('RGB', (640, 480), color=(i*5, i*5, i*5))
    d = ImageDraw.Draw(img)
    text = texts.get(i, f"FRAME {i}")
    d.text((10,10), text, fill=(255,255,255))
    path = f"/app/frames/frame_{i:04d}.png"
    img.save(path)

    with open(path, 'rb') as f:
        h = hashlib.md5(f.read()).hexdigest()

    if i in texts:
        hashes[h] = texts[i]

subprocess.run(['ffmpeg', '-y', '-framerate', '10', '-i', '/app/frames/frame_%04d.png', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '/app/leak_recording.mp4'], check=True)

with open('/app/extract_text.py', 'w') as f:
    f.write(f'''import sys, hashlib
if len(sys.argv) < 2: sys.exit(1)
with open(sys.argv[1], "rb") as f:
    h = hashlib.md5(f.read()).hexdigest()
hashes = {hashes}
print(hashes.get(h, ""))
''')

# 2. Generate Corpora
key = b"4a2b9c118f7e6d5c2233445566778899"

clean_data = [
    b"SELECT * FROM users WHERE id = 5;",
    b"<div class=\"main\">Welcome to the dashboard</div>",
    b"Error: unexpected token '<' in config.json",
    b"SELECT username, email FROM accounts;"
] * 5

evil_data = [
    b"SELECT * FROM users WHERE id = 5 UNION SELECT 1, password FROM admin;",
    b"<scr<script>ipt>alert('XSS')</script>",
    b"user_input=1'; DROP TABLE users--",
    b"<img src=x onerror=alert(1)>"
] * 5

for i, d in enumerate(clean_data):
    # Pad to multiple of 16 bytes for no-padding requirement
    pad_len = (16 - len(d) % 16) % 16
    d = d + b' ' * pad_len
    if len(d) % 16 != 0: d = d.ljust(len(d) + 16 - (len(d)%16), b' ')

    with open(f'/test_data/unencrypted_corpora/clean/file_{i}.txt', 'wb') as f:
        f.write(d)
    iv = os.urandom(16)
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
    encryptor = cipher.encryptor()
    ct = encryptor.update(d) + encryptor.finalize()
    with open(f'/app/encrypted_corpora/clean/file_{i}.txt', 'wb') as f:
        f.write(iv + ct)

for i, d in enumerate(evil_data):
    pad_len = (16 - len(d) % 16) % 16
    d = d + b' ' * pad_len
    if len(d) % 16 != 0: d = d.ljust(len(d) + 16 - (len(d)%16), b' ')

    with open(f'/test_data/unencrypted_corpora/evil/file_{i}.txt', 'wb') as f:
        f.write(d)
    iv = os.urandom(16)
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
    encryptor = cipher.encryptor()
    ct = encryptor.update(d) + encryptor.finalize()
    with open(f'/app/encrypted_corpora/evil/file_{i}.txt', 'wb') as f:
        f.write(iv + ct)
EOF

    python3 /tmp/setup.py
    rm -rf /app/frames /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /test_data
    chmod -R 777 /home/user
