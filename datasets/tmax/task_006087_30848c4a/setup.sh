#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import datetime

log_path = "/home/user/server_metrics.log"
start_time = datetime.datetime(2023, 10, 1, 10, 0, 0)
cpu_sequence = [20.0, 21.0, 22.0, 23.0, 24.0] # average is 22.0

anomalies_injected = {
    1000: 55.5,
    5000: 88.8,
    9000: 99.9
}

with open(log_path, "w") as f:
    for i in range(10000):
        current_time = start_time + datetime.timedelta(seconds=i)
        time_str = current_time.strftime("%Y-%m-%d %H:%M:%S")

        if i in anomalies_injected:
            cpu = anomalies_injected[i]
        else:
            cpu = cpu_sequence[i % len(cpu_sequence)]

        f.write(f"[{time_str}] INFO - CPU: {cpu:.1f}% RAM: 2048MB STATUS: OK\n")

os.chmod(log_path, 0o644)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
