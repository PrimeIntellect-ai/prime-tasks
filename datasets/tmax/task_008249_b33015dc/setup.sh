#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/setup_data.py
import json
import random

random.seed(42)

servers = [f"server_{i:03d}" for i in range(10)]
base_config = {f"key{i}": "val0" for i in range(10)}

for file_idx in range(3):
    with open(f"/home/user/data/logs_{file_idx}.jsonl", "w") as f:
        for t in range(20):
            for s in servers:
                # Randomize timestamp slightly
                ts = 1600000000 + t * 3600 + file_idx * 86400 + random.randint(0, 60)

                # Copy and occasionally mutate config
                cfg = base_config.copy()
                if random.random() < 0.2:
                    # Minor mutation
                    cfg[f"key{random.randint(0, 9)}"] = f"val{random.randint(1, 5)}"
                elif random.random() < 0.05:
                    # Major mutation (anomaly)
                    for k in range(5):
                        cfg[f"key{random.randint(0, 9)}"] = f"val{random.randint(10, 20)}"

                f.write(json.dumps({"server_id": s, "timestamp": ts, "config": cfg}) + "\n")
EOF

    python3 /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
