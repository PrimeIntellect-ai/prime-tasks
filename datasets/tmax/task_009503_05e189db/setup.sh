#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import csv
import json

data = [
    ("alpha", [1.0, -1.0, 0.0], [[0.0, 1.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]),
    ("alpha", [0.0, 2.0, 0.0], [[0.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 0.0]]),
    ("beta", [2.0, 1.0, 1.0], [[0.5, 0.0, 0.0], [0.0, 0.5, 0.0], [0.0, 0.0, 0.2]]),
    ("beta", [1.0, 1.0, -1.0], [[1.0, 0.0, 0.0], [0.0, 0.5, 0.0], [0.0, 0.0, -0.2]]),
    ("gamma", [-1.0, -1.0, -1.0], [[1.0, 1.0, 1.0], [1.0, 1.0, 1.0], [1.0, 1.0, 1.0]]),
    ("gamma", [1.0, 0.0, 0.0], [[-1.0, -0.5, -0.2], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]),
    ("delta", [0.0, 0.0, 1.0], [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 2.0]]),
]

with open('/home/user/experiments.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['exp_group', 'input_vector', 'weight_matrix'])
    for group, inp, weights in data:
        writer.writerow([group, json.dumps(inp), json.dumps(weights)])
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
