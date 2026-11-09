#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/incident_044.wav "restart cluster maintenance override"

    mkdir -p /home/user/daemon
    cat << 'EOF' > /home/user/daemon/processor.py
import sys
import json

def parse_command_tree(node, tree):
    if node not in tree:
        return []
    res = []
    for child in tree[node]:
        res.append(child)
        res.extend(parse_command_tree(child, tree))
    return res

if __name__ == "__main__":
    if "--test" in sys.argv:
        tree = {
            "restart": ["cluster"],
            "cluster": ["maintenance"],
            "maintenance": ["override"],
            "override": ["restart"]
        }
        res = parse_command_tree("restart", tree)
        if res == {"error": "circular reference detected"}:
            print(json.dumps(res))
        else:
            print(json.dumps({"result": "success"}))
EOF

    cat << 'EOF' > /tmp/gen_logs.py
import os
import random

os.makedirs("/app/clean_logs", exist_ok=True)
os.makedirs("/app/evil_logs", exist_ok=True)

for i in range(50):
    with open(f"/app/clean_logs/log_{i}.txt", "w") as f:
        ts = 1600000000
        for _ in range(100):
            ts += random.randint(1, 5)
            lat = max(1, int(random.gauss(15, 2)))
            f.write(f"{ts} INFO ping latency={lat}ms\n")

    with open(f"/app/evil_logs/log_{i}.txt", "w") as f:
        ts = 1600000000
        for j in range(100):
            if j == 50:
                ts -= random.randint(10, 50)
                lat = random.randint(501, 1000)
            else:
                ts += random.randint(1, 5)
                lat = max(1, int(random.gauss(15, 2)))
            f.write(f"{ts} INFO ping latency={lat}ms\n")
EOF
    python3 /tmp/gen_logs.py
    rm /tmp/gen_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
