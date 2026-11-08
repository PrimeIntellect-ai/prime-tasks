#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr cargo
    pip3 install pytest networkx pillow

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    cat << 'EOF' > /tmp/gen_data.py
import networkx as nx
import os
from PIL import Image, ImageDraw

# Generate image
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), "TARGET_MEAN=5.0\nMAX_KS_STAT=0.15", fill=(0, 0, 0))
img.save('/app/model_spec.png')

# Generate graphs
for i in range(20):
    G_clean = nx.erdos_renyi_graph(100, 0.05)
    nx.write_edgelist(G_clean, f'/app/corpora/clean/graph_{i}.txt', data=False)

    G_evil = nx.erdos_renyi_graph(100, 0.15)
    nx.write_edgelist(G_evil, f'/app/corpora/evil/graph_{i}.txt', data=False)
EOF

    python3 /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
