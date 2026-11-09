#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/auth_payload.wav "Emergency security update. Please block the malicious IP address ten dot zero dot five dot twenty two immediately."

    # Generate access.log and golden_filtered.log
    cat << 'EOF' > /tmp/generate_logs.py
import random

random.seed(42)
ips = ["10.0.5.22"] + [f"192.168.1.{i}" for i in range(1, 100)]
methods = ["GET", "POST", "PUT", "DELETE"]
paths = ["/index.html", "/api/data", "/login", "/logout"]

start_ts = 1600000000
entries = []
for i in range(500000):
    ts = start_ts + random.randint(0, 3600)
    ip = random.choice(ips)
    method = random.choice(methods)
    path = random.choice(paths)
    entries.append((ts, ip, method, path))

entries.sort(key=lambda x: x[0])

with open("/app/access.log", "w") as f_in, open("/app/golden_filtered.log", "w") as f_out:
    rate_limits = {}
    for ts, ip, method, path in entries:
        line = f"{ts} {ip} {method} {path}\n"
        f_in.write(line)

        if ip == "10.0.5.22":
            continue

        minute = ts // 60
        key = (ip, minute)
        rate_limits[key] = rate_limits.get(key, 0) + 1

        if rate_limits[key] <= 5:
            f_out.write(line)
EOF

    python3 /tmp/generate_logs.py
    rm /tmp/generate_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
