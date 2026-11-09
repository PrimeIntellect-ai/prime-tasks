#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/generate_logs.py
import random
from datetime import datetime, timedelta

random.seed(42)
lines = []

# Hour 10: 50 requests, 2 errors (4%) - Not flagged
for _ in range(48):
    lines.append(f"[2023-10-25 10:{random.randint(0,59):02d}:{random.randint(0,59):02d}] 192.168.1.100 GET /index.html 1.1 200")
for _ in range(2):
    lines.append(f"[2023-10-25 10:{random.randint(0,59):02d}:{random.randint(0,59):02d}] 192.168.1.101 POST /api/submit 1.1 500")

# Hour 11: 40 requests, 4 errors (10%) - FLAGGED
for _ in range(36):
    lines.append(f"[2023-10-25 11:{random.randint(0,59):02d}:{random.randint(0,59):02d}] 10.0.0.5 GET /images/logo.png 1.1 200")
for _ in range(4):
    lines.append(f"[2023-10-25 11:{random.randint(0,59):02d}:{random.randint(0,59):02d}] 10.0.0.6 GET /api/data 1.1 503")

# Hour 12: 100 requests, 8 errors (8%) - FLAGGED
for _ in range(92):
    lines.append(f"[2023-10-25 12:{random.randint(0,59):02d}:{random.randint(0,59):02d}] 172.16.0.2 GET /about 1.1 200")
for _ in range(8):
    lines.append(f"[2023-10-25 12:{random.randint(0,59):02d}:{random.randint(0,59):02d}] 172.16.0.3 POST /login 1.1 500")

# Shuffle to simulate realistic log append orders
random.shuffle(lines)

with open("/home/user/data/server_logs.txt", "w") as f:
    for line in lines:
        f.write(line + "\n")
EOF

    python3 /home/user/generate_logs.py
    rm /home/user/generate_logs.py

    chmod -R 777 /home/user
