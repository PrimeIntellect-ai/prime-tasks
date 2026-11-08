#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr libtesseract-dev build-essential nlohmann-json3-dev
    pip3 install pytest Pillow

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create the routing_memo.png using Python
    cat << 'EOF' > /tmp/make_img.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 50), "RULE: DENY ANY PATH CONTAINING NODE 'PROXY-99'. DENY IF total_cost > 5000.", fill=(0, 0, 0))
img.save('/app/routing_memo.png')
EOF
    python3 /tmp/make_img.py
    rm /tmp/make_img.py

    # Create clean corpus
    cat << 'EOF' > /app/corpora/clean/1.json
{"schema_version": "2.0", "path_id": "p1", "nodes": ["A", "B"], "total_cost": 1000}
EOF
    cat << 'EOF' > /app/corpora/clean/2.json
{"schema_version": "2.0", "path_id": "p2", "nodes": ["C"], "total_cost": 5000}
EOF
    cat << 'EOF' > /app/corpora/clean/3.json
{"schema_version": "2.0", "path_id": "p3", "nodes": ["PROXY-1"], "total_cost": 0}
EOF
    cat << 'EOF' > /app/corpora/clean/4.json
{"schema_version": "2.0", "path_id": "p4", "nodes": [], "total_cost": 4999}
EOF
    cat << 'EOF' > /app/corpora/clean/5.json
{"schema_version": "2.0", "path_id": "p5", "nodes": ["X", "Y", "Z"], "total_cost": 2500}
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpora/evil/1.json
{"schema_version": "1.0", "path_id": "e1", "nodes": ["A"], "total_cost": 100}
EOF
    cat << 'EOF' > /app/corpora/evil/2.json
{"schema_version": "2.0", "path_id": "e2", "nodes": ["PROXY-99"], "total_cost": 100}
EOF
    cat << 'EOF' > /app/corpora/evil/3.json
{"schema_version": "2.0", "path_id": "e3", "nodes": ["A"], "total_cost": 5001}
EOF
    cat << 'EOF' > /app/corpora/evil/4.json
{"schema_version": "2.0", "path_id": "e4", "nodes": "A", "total_cost": 100}
EOF
    cat << 'EOF' > /app/corpora/evil/5.json
{"schema_version": "2.0", "path_id": "e5", "nodes": ["A"]}
EOF
    cat << 'EOF' > /app/corpora/evil/6.json
{"schema_version": "2.0" "path_id": "e6"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
