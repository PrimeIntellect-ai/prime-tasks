#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang ffmpeg jq
    pip3 install pytest Pillow

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate clean corpus
    cat << 'EOF' > /app/corpus/clean/clean1.json
{"device_id":"A1B2c3D4", "ip_address":"192.168.1.1", "temperature": 45.2}
EOF
    cat << 'EOF' > /app/corpus/clean/clean2.json
{"device_id":"12345678", "ip_address":"10.0.0.1", "temperature": -50.0}
EOF
    cat << 'EOF' > /app/corpus/clean/clean3.json
{"device_id":"abcdefgh", "ip_address":"172.16.0.1", "temperature": 150.0}
EOF
    cat << 'EOF' > /app/corpus/clean/clean4.json
{"device_id":"A1B2c3D4", "ip_address":"8.8.8.8", "temperature": 0.0}
EOF
    cat << 'EOF' > /app/corpus/clean/clean5.json
{"device_id":"A1B2c3D4", "ip_address":"1.1.1.1", "temperature": 99.9}
EOF

    # Generate evil corpus
    cat << 'EOF' > /app/corpus/evil/evil1.json
{"device_id":"A1B2c3D4", "ip_address":"256.1.1.1", "temperature": 45.2}
EOF
    cat << 'EOF' > /app/corpus/evil/evil2.json
{"device_id":"A1B2", "ip_address":"192.168.1.1", "temperature": 45.2}
EOF
    cat << 'EOF' > /app/corpus/evil/evil3.json
{"device_id":"A1B2c3D4E5", "ip_address":"192.168.1.1", "temperature": 45.2}
EOF
    cat << 'EOF' > /app/corpus/evil/evil4.json
{"device_id":"A1B2c-D4", "ip_address":"192.168.1.1", "temperature": 45.2}
EOF
    cat << 'EOF' > /app/corpus/evil/evil5.json
{"device_id":"A1B2c3D4", "ip_address":"192.168.1.1", "temperature": -51.0}
EOF
    cat << 'EOF' > /app/corpus/evil/evil6.json
{"device_id":"A1B2c3D4", "ip_address":"192.168.1.1", "temperature": 150.1}
EOF
    cat << 'EOF' > /app/corpus/evil/evil7.json
{"device_id":"A1B2c3D4", "ip_address":"192.168.1.1", "temperature": 999.0}
EOF
    cat << 'EOF' > /app/corpus/evil/evil8.json
{"device_id":"A1B2c3D4", "ip_address":"127.0.0.1; rm -rf /", "temperature": 45.2}
EOF
    cat << 'EOF' > /app/corpus/evil/evil9.json
{"device_id":"A1B2c3D4", "ip_address":"192.168.1.1"}
EOF
    cat << 'EOF' > /app/corpus/evil/evil10.json
{"device_id":"A1B2c3D4", "ip_address":"192.168.1.1", "temperature": "45.2"}
EOF

    # Generate video frames and compile video
    cat << 'EOF' > /tmp/gen_frames.py
import os
from PIL import Image

os.makedirs("/tmp/frames", exist_ok=True)
for i in range(100):
    color = "white" if 42 <= i <= 46 else "black"
    img = Image.new("RGB", (100, 100), color)
    img.save(f"/tmp/frames/frame_{i:03d}.png")
EOF
    python3 /tmp/gen_frames.py
    ffmpeg -y -framerate 10 -i /tmp/frames/frame_%03d.png -c:v libx264 -pix_fmt yuv420p /app/camera_feed.mp4
    rm -rf /tmp/frames /tmp/gen_frames.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
