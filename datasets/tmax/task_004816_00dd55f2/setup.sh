#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data_pipeline
    cd /home/user/data_pipeline

    cat << 'EOF' > generate_data.py
import random

random.seed(42)
with open("raw_sensors.csv", "w") as f:
    for i in range(10000):
        timestamp = 1600000000 + i * 10
        sensor_id = random.randint(1, 5)
        value = random.uniform(10.0, 100.0)
        f.write(f"{timestamp},{sensor_id},{value:.4f}\n")
EOF

    python3 generate_data.py
    rm generate_data.py

    chmod -R 777 /home/user
