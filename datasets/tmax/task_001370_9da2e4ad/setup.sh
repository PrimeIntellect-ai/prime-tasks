#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr libtesseract-dev curl
    pip3 install pytest pillow

    mkdir -p /app

    cat << 'EOF' > /app/transactions.jsonl
{"src": "U1", "dst": "U2", "amount": 150}
{"src": "U2", "dst": "U3", "amount": 300}
{"src": "U1", "dst": "U3", "amount": 50}
{"src": "U3", "dst": "U4", "amount": 10}
{"src": "U4", "dst": "U1", "amount": 200}
EOF

    cat << 'EOF' > /tmp/generate_image.py
from PIL import Image, ImageDraw

text = """Host: 127.0.0.1
Port: 8888

Endpoints required:
1. GET /graph/centrality
Returns the node with the highest PageRank (alpha=0.85) in the transaction graph.
Response format: {"top_node": "<node_id>"}

2. POST /nosql/aggregate
Accepts JSON: {"min_amount": <float>}
Returns the total amount sent by the user who sent the most money in total, considering only transactions >= min_amount.
Response format: {"top_sender_volume": <float>}"""

img = Image.new('RGB', (800, 600), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/architecture.png')
EOF

    python3 /tmp/generate_image.py
    rm /tmp/generate_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
