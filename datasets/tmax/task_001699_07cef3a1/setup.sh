#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/models

    # Create dummy model artifacts
    dd if=/dev/zero of=/home/user/models/model_fast.bin bs=1 count=1500 2>/dev/null
    dd if=/dev/zero of=/home/user/models/model_balanced.bin bs=1 count=4500 2>/dev/null
    dd if=/dev/zero of=/home/user/models/model_heavy.bin bs=1 count=12000 2>/dev/null

    # Create the benchmark script
    cat << 'EOF' > /home/user/benchmark.py
import sys
import json
import os

if len(sys.argv) != 2:
    sys.exit(1)

model_path = sys.argv[1]
if not os.path.exists(model_path):
    sys.exit(1)

size = os.path.getsize(model_path)
filename = os.path.basename(model_path)

# Deterministic mock metrics
latency = (size * 0.02) + len(filename)
throughput = 50000.0 / latency if latency > 0 else 0

print(json.dumps({
    "latency_ms": round(latency, 2),
    "throughput": round(throughput, 2)
}))
EOF
    chmod +x /home/user/benchmark.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
