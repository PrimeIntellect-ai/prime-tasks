#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import random
from datetime import datetime, timedelta

base_dir = "/home/user/project_logs"
os.makedirs(base_dir, exist_ok=True)

start_date = datetime(2023, 10, 1)

logs = [
    (10, "INFO", "System startup initiated", False),
    (25, "ERROR", "Failed to connect to DB\nTimeout exceeded\nRetrying...", True),
    (40, "INFO", "Connected to DB", False),
    (120, "CRITICAL", "Out of memory\nCore dumped", True),
    (150, "ERROR", "Missing config file", False),
    (200, "INFO", "Shutting down", False)
]

random.seed(42)

for i in range(5):
    sub_dir = os.path.join(base_dir, f"region_{i}", f"server_{random.randint(1, 10)}")
    os.makedirs(sub_dir, exist_ok=True)

    for j in range(3):
        file_path = os.path.join(sub_dir, f"app_{j}.log")
        with open(file_path, "w") as f:
            for offset, level, msg, multi in logs:
                jitter = random.randint(1, 1000) * (i + 1) * (j + 1)
                ts = start_date + timedelta(seconds=offset + jitter)
                f.write(f"[{ts.strftime('%Y-%m-%d %H:%M:%S')}] [{level}] {msg}\n")
EOF

    python3 /tmp/setup.py

    chmod -R 777 /home/user
