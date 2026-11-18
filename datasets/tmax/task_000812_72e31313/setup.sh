#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app/data

    # Generate the auth_spec.png image using Python and Pillow
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (200, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), 'PORT: 9055', fill=(0, 0, 0))
d.text((10, 50), 'TOKEN: f9a8b7c6', fill=(0, 0, 0))
img.save('/app/auth_spec.png')
"

    # Create base.csv
    cat << 'EOF' > /app/data/base.csv
service,cpu,mem
auth,2,1024
web,4,2048
db,8,8192
EOF

    # Create changes.jsonl
    cat << 'EOF' > /app/data/changes.jsonl
{"time": "2024-01-01T08:15:00", "service": "web", "cpu": 6, "mem": 4096, "note": "Scale up web"}
{"time": "2024-01-01T09:00:00", "service": "db", "cpu": 0, "mem": 8192, "note": "Invalid scale down"}
{"time": "2024-01-01T10:30:00", "service": "auth", "cpu": 4, "mem": 2048, "note": "Fix auth \u001Z bad unicode"}
{"time": "2024-01-02T12:00:00", "service": "db", "cpu": 16, "mem": 16384, "note": "Scale up db"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
