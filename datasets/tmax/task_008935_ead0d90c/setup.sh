#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/generate_data.py
import math

with open("/home/user/sensor_data.csv", "w") as f:
    start_ts = 1700000000
    for i in range(1, 150001):
        ts = start_ts + (i * 10)
        val = math.sin(i / 100.0) * 50.0 + 25.0
        f.write(f"{ts},{val:.6f}\n")
EOF
    python3 /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
