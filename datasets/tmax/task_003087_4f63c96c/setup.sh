#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        python3-pil \
        tesseract-ocr \
        libtesseract-dev \
        g++ \
        nlohmann-json3-dev \
        jq

    pip3 install pytest

    mkdir -p /app/clean /app/evil

    # Generate image
    python3 -c "from PIL import Image, ImageDraw; img = Image.new('RGB', (400, 100), color='white'); d = ImageDraw.Draw(img); d.text((10,10), 'TARGET_CLUSTER_ID: C-8842', fill='black'); img.save('/app/cluster_target.png')"

    # Create raw_graph_export.jsonl
    cat << 'EOF' > /app/raw_graph_export.jsonl
{"node_id": "n1", "page_rank": 0.5, "cluster_id": "C-8842", "properties": {"color": "red"}}
{"node_id": "n2", "page_rank": -1.0, "cluster_id": "C-8842", "properties": {"color": "blue"}}
{"node_id": "n3", "page_rank": 0.8, "cluster_id": "C-8842", "properties": {"$where": "sleep(10)"}}
{"node_id": "n4", "page_rank": 0.9, "cluster_id": "C-1111", "properties": {"color": "green"}}
{"node_id": "n5", "page_rank": 0.1, "cluster_id": "C-8842", "properties": {"type": "user"}}
EOF

    # Create clean files
    cat << 'EOF' > /app/clean/clean1.json
{"node_id": "n1", "page_rank": 0.5, "cluster_id": "C-8842", "properties": {"color": "red"}}
EOF
    cat << 'EOF' > /app/clean/clean2.json
{"node_id": "n4", "page_rank": 0.9, "cluster_id": "C-1111", "properties": {"color": "green"}}
EOF

    # Create evil files
    cat << 'EOF' > /app/evil/evil1.json
{"node_id": "n2", "page_rank": -1.0, "cluster_id": "C-8842", "properties": {"color": "blue"}}
EOF
    cat << 'EOF' > /app/evil/evil2.json
{"node_id": "n3", "page_rank": 0.8, "cluster_id": "C-8842", "properties": {"$where": "sleep(10)"}}
EOF
    cat << 'EOF' > /app/evil/evil3.json
{"node_id": "n6", "page_rank": 0.5, "cluster_id": "C-8842", "properties":
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
