#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    imagemagick \
    tesseract-ocr \
    libtesseract-dev \
    cargo \
    rustc \
    curl

pip3 install pytest

mkdir -p /app
convert -size 400x100 xc:white -fill black -pointsize 24 -draw "text 10,50 'AUDIT_NODE: TX_88192'" /app/alert_screenshot.png

cat << 'EOF' > /tmp/gen_data.py
import random

def generate_csv(path, num_edges, target_cycle):
    edges = set()
    with open(path, 'w') as f:
        for _ in range(num_edges):
            w = f"TX_{random.randint(10000, 99999)}"
            h = f"TX_{random.randint(10000, 99999)}"
            edges.add((w, h))

        for i in range(len(target_cycle)):
            edges.add((target_cycle[i], target_cycle[(i+1)%len(target_cycle)]))

        for w, h in edges:
            f.write(f"{w},{h},1690000000\n")

# Generate the sample data
generate_csv('/app/locks.csv', 50000, ["TX_88192", "TX_11111", "TX_22222", "TX_33333"])

# Generate the hidden verification data
generate_csv('/tmp/hidden_locks.csv', 2000000, ["TX_99999", "TX_A", "TX_B", "TX_C", "TX_D"])
EOF

python3 /tmp/gen_data.py
rm /tmp/gen_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
chmod 777 /tmp/hidden_locks.csv
