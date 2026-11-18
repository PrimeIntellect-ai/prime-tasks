#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /tmp/setup.py
from PIL import Image, ImageDraw
import json

# Generate image
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "SUBNET: 172.16.0.0/12\nRESTRICTED_PORT: 8080\nQUOTA_MB: 500.0"
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/topology_diagram.png')

# Generate clean logs
for i in range(20):
    with open(f'/app/corpus/clean/log_{i}.json', 'w') as f:
        json.dump({"source_ip": f"172.16.0.{i+1}", "dest_port": 80, "log_size_mb": 100.0}, f)

# Generate evil logs
for i in range(20):
    with open(f'/app/corpus/evil/log_{i}.json', 'w') as f:
        json.dump({"source_ip": f"192.168.1.{i+1}", "dest_port": 8080, "log_size_mb": 600.0}, f)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
