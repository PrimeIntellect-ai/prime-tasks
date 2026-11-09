#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > generate_data.py
import random
random.seed(42)

ips = [f"192.168.1.{i}" for i in range(1, 51)]
labels = {}

with open("labels.csv", "w") as f:
    for ip in ips:
        label = 1 if random.random() > 0.5 else 0
        labels[ip] = label
        f.write(f"{ip},{label}\n")

with open("raw_logs.txt", "w") as f:
    for _ in range(500):
        ip = random.choice(ips)
        is_bot = labels[ip] == 1

        # Bots make more requests, have smaller payloads, and faster responses
        resp_time = int(random.gauss(50, 10)) if is_bot else int(random.gauss(200, 40))
        payload = int(random.gauss(500, 100)) if is_bot else int(random.gauss(5000, 1000))

        resp_time = max(1, resp_time)
        payload = max(10, payload)

        f.write(f"2023-10-01T12:00:00Z | {ip} | {resp_time} | {payload}\n")
EOF
    python3 generate_data.py
    rm generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
