#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import json
import random

os.makedirs('/home/user/artifacts', exist_ok=True)

random.seed(42)
total_metric = 0

for i in range(1000):
    deps = []
    num_deps = random.randint(5, 50)
    manifest_metric = 0
    for j in range(num_deps):
        size = random.randint(1024, 1048576)
        deps.append({
            "name": f"lib_{j}.so",
            "size_bytes": size
        })
        manifest_metric += (size * (j + 1)) % 9973

    total_metric += manifest_metric

    manifest = {
        "artifact_id": f"art_{i}",
        "timestamp": "2023-10-01T12:00:00Z",
        "dependencies": deps
    }

    with open(f'/home/user/artifacts/manifest_{i}.json', 'w') as f:
        json.dump(manifest, f)

with open('/home/user/expected_total.txt', 'w') as f:
    f.write(str(total_metric))
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
