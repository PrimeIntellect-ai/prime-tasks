#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg cargo rustc
    pip3 install pytest Pillow

    mkdir -p /app/eval

    cat << 'EOF' > /app/eval/clean_corpus.jsonl
{"military_zone": false, "device_id": "device-1234", "battery_temp": 45.2, "data": "..."}
{"military_zone": false, "device_id": "ABCDEF123456", "battery_temp": 89.9}
EOF

    cat << 'EOF' > /app/eval/evil_corpus.jsonl
{"military_zone": true, "device_id": "device-1234", "battery_temp": 45.2}
{"military_zone": false, "device_id": "00:11:22:33:44:55", "battery_temp": 45.2}
{"military_zone": false, "device_id": "device-1234", "battery_temp": 90.1}
{"military_zone": false, "device_id": "aa:bb:cc:dd:ee:ff", "battery_temp": 20.0}
EOF

    cat << 'EOF' > /tmp/gen_video.py
from PIL import Image
import os
os.makedirs('/tmp/frames', exist_ok=True)
for i in range(100):
    color = (255, 0, 0) if i in [14, 42, 89] else (0, 0, 0)
    img = Image.new('RGB', (64, 64), color)
    img.save(f'/tmp/frames/frame_{i:03d}.png')
EOF

    python3 /tmp/gen_video.py
    ffmpeg -y -framerate 10 -i /tmp/frames/frame_%03d.png -c:v libx264 -pix_fmt yuv420p /app/flight_video.mp4
    rm -rf /tmp/frames /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
