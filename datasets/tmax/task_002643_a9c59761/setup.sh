#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user/data
    cd /home/user/data

    cat << 'EOF' > generate_data.py
import json
import random

random.seed(42)

# Generate raw_sensor.csv
with open('raw_sensor.csv', 'w') as f:
    for i in range(1, 51):
        features = [random.gauss(0, 1) for _ in range(10)]
        row = [i] + features
        f.write(",".join(map(str, row)) + "\n")

# Generate model_weights.json
weights = [[random.gauss(0, 0.5) for _ in range(2)] for _ in range(10)]
with open('model_weights.json', 'w') as f:
    json.dump(weights, f)
EOF

    python3 generate_data.py
    rm generate_data.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
