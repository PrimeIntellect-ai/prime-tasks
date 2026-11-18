#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_logs.py
import os
import datetime

os.makedirs('/home/user/raw_logs', exist_ok=True)

start_epoch = 1696154400

logs_eu = []
logs_us = []
logs_asia = []

for m in range(0, 60):
    current_epoch = start_epoch + (m * 60)
    dt = datetime.datetime.utcfromtimestamp(current_epoch)

    if 25 <= m < 30:
        latency_ms = 400.0
    else:
        latency_ms = 100.0

    eu_time = dt.strftime("%d/%m/%Y %H:%M:%S")
    logs_eu.append(f"{eu_time} | OK\xa0 | {latency_ms}")

    us_time = dt.strftime("%Y-%m-%dT%H:%M:%SZ")
    logs_us.append(f"{us_time} | OK | {latency_ms / 1000.0}")

    asia_time = int(current_epoch * 1000)
    logs_asia.append(f"{asia_time} | OK | {latency_ms * 1000.0}")

with open('/home/user/raw_logs/server_eu.log', 'w', encoding='iso-8859-1') as f:
    f.write("\n".join(logs_eu))

with open('/home/user/raw_logs/server_us.log', 'w', encoding='utf-8') as f:
    f.write("\n".join(logs_us))

with open('/home/user/raw_logs/server_asia.log', 'w', encoding='utf-16le') as f:
    f.write("\n".join(logs_asia))
EOF

    python3 /tmp/setup_logs.py
    chown -R user:user /home/user/raw_logs
    chmod -R 777 /home/user
