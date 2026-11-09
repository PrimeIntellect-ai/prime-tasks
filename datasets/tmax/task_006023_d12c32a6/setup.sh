#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_data.py
import json
import random

hosts = [f"web{str(i).zfill(2)}" for i in range(1, 21)]
processes = ["nginx", "java", "python", "node", "mysql", "redis", "fluentd"]

data = []
random.seed(42)
for _ in range(5000):
    host = random.choice(hosts)
    process = random.choice(processes)
    memory = round(random.uniform(10.0, 4096.0), 2)
    data.append({"host": host, "process": process, "memory_mb": memory})

with open("/home/user/metrics.jsonl", "w") as f:
    for row in data:
        f.write(json.dumps(row) + "\n")
EOF
    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    chmod -R 777 /home/user
