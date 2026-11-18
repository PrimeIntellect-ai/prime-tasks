#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest Pillow

    mkdir -p /app

    cat << 'EOF' > /tmp/setup.py
import json
import base64
from PIL import Image, ImageDraw

# Generate responses.jsonl
records = [
    {"version": "1.9.0", "A": 10, "B": 5, "C": 2},
    {"version": "2.1.4", "A": 20, "B": 1, "C": 3},
    {"version": "2.1.5", "A": 5,  "B": 10, "C": 4},
    {"version": "2.2.0", "A": 2,  "B": 5,  "C": 10},
    {"version": "3.0.0", "A": 8,  "B": 2,  "C": 6},
    {"version": "2.1.5-alpha", "A": 100, "B": 100, "C": 100}
]

with open('/app/responses.jsonl', 'w') as f:
    for r in records:
        payload = json.dumps({"A": r["A"], "B": r["B"], "C": r["C"]}).encode('utf-8')
        encoded = base64.b64encode(payload).decode('utf-8')
        f.write(json.dumps({"version": r["version"], "payload": encoded}) + '\n')

# Generate api_spec.png
img = Image.new('RGB', (600, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "API Evaluation Specification\nMinimum Version: 2.1.5\nScore Formula: (A * C) + B"
d.text((20, 40), text, fill=(0, 0, 0))
img.save('/app/api_spec.png')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
