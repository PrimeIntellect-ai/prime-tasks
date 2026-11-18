#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import json
import random
import os

random.seed(42)
zones = []
for _ in range(10000):
    zones.append({
        "x": round(random.uniform(0, 1000), 2),
        "y": round(random.uniform(0, 1000), 2),
        "base_cost": round(random.uniform(5, 20), 2),
        "multiplier": round(random.uniform(0.5, 2.0), 2)
    })

with open("/home/user/delivery_zones.json", "w") as f:
    json.dump(zones, f)

queries = []
for _ in range(500):
    queries.append({
        "qx": round(random.uniform(0, 1000), 2),
        "qy": round(random.uniform(0, 1000), 2),
        "radius": round(random.uniform(10, 50), 2)
    })

with open("/home/user/queries.json", "w") as f:
    json.dump(queries, f)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
