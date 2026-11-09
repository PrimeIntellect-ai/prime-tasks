#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest scikit-learn pandas numpy pillow

    mkdir -p /app

    cat << 'EOF' > /tmp/setup.py
import json
from PIL import Image, ImageDraw

img = Image.new('RGB', (400, 50), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), "Query: memory leak in distributed training module", fill=(0, 0, 0))
img.save('/app/query.png')

logs = [
    {"id": 1, "log_text": "Started distributed training module on 4 GPUs.", "latency_ms": 120.5, "vram_mb": 4096.0},
    {"id": 2, "log_text": "Warning: memory leak detected in distributed training module.", "latency_ms": 450.2, "vram_mb": 15000.0},
    {"id": 3, "log_text": "GPU out of memory during backward pass.", "latency_ms": 800.0, "vram_mb": 16384.0},
    {"id": 4, "log_text": "Epoch 1 completed successfully.", "latency_ms": 50.0, "vram_mb": 2048.0},
    {"id": 5, "log_text": "Loading data into memory.", "latency_ms": 20.0, "vram_mb": 512.0},
    {"id": 6, "log_text": "Memory leak in data loader.", "latency_ms": 300.0, "vram_mb": 8192.0},
    {"id": 7, "log_text": "Distributed training module initialized.", "latency_ms": 100.0, "vram_mb": 1024.0},
]

with open('/app/logs.json', 'w') as f:
    json.dump(logs, f)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
