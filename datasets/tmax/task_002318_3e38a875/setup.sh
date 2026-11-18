#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

# Install required system packages
apt-get install -y ffmpeg qrencode zbar-tools netcat-openbsd curl socat

# Create app directory
mkdir -p /app

# Generate the video artifact
cat << 'EOF' > /tmp/generate_video.py
import os
import hashlib
import base64
import subprocess

def xor_hex(hex1, hex2):
    return f"{int(hex1, 16) ^ int(hex2, 16):016x}"

master_key = "c0ffee00deadbeef"

plaintexts = [
    "0000000000000000",
    "1111111111111111",
    "2222222222222222",
    "3333333333333333"
]

os.makedirs("/tmp/frames", exist_ok=True)

for i, pt in enumerate(plaintexts):
    ct = xor_hex(pt, master_key)

    m = hashlib.sha256()
    m.update(ct.encode('utf-8'))
    true_hash = m.hexdigest()

    if i == 2:
        payload_str = f"PT:{pt}|CT:{ct}|HASH:0000000000000000000000000000000000000000000000000000000000000000"
    else:
        payload_str = f"PT:{pt}|CT:{ct}|HASH:{true_hash}"

    b64_payload = base64.b64encode(payload_str.encode('utf-8')).decode('utf-8')

    frame_path = f"/tmp/frames/frame_{i}.png"
    # Use -s 10 to ensure the image dimensions are large enough and likely even
    subprocess.run(["qrencode", "-s", "10", "-o", frame_path, b64_payload], check=True)

# Generate a 4-second video at 1 fps from the frames
subprocess.run([
    "ffmpeg", "-y", "-framerate", "1", "-i", "/tmp/frames/frame_%d.png",
    "-c:v", "libx264", "-r", "30", "-pix_fmt", "yuv420p", "/app/credential_sync.mp4"
], check=True)

EOF

python3 /tmp/generate_video.py
rm -rf /tmp/frames /tmp/generate_video.py

# Create user
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
