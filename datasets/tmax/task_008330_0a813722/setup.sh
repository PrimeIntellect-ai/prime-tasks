#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_logs.py
import random

with open('/home/user/system_events.txt', 'w') as f:
    # Subnet 1: Drop anomaly
    for _ in range(100):
        f.write(f"2023-10-01T10:{random.randint(10,59)}:00 192.168.1.{random.randint(1,254)} LOGIN 200\n")
    for _ in range(15):
        f.write(f"2023-10-01T11:{random.randint(10,59)}:00 192.168.1.{random.randint(1,254)} LOGIN 200\n")

    # Subnet 2: Normal behavior (no anomaly)
    for _ in range(80):
        f.write(f"2023-10-01T10:{random.randint(10,59)}:00 10.0.5.{random.randint(1,254)} LOGIN 200\n")
    for _ in range(90):
        f.write(f"2023-10-01T11:{random.randint(10,59)}:00 10.0.5.{random.randint(1,254)} LOGIN 200\n")

    # Subnet 3: Drop anomaly
    for _ in range(60):
        f.write(f"2023-10-01T14:{random.randint(10,59)}:00 172.16.20.{random.randint(1,254)} LOGOUT 200\n")
    for _ in range(10):
        f.write(f"2023-10-01T15:{random.randint(10,59)}:00 172.16.20.{random.randint(1,254)} LOGOUT 200\n")

    # Subnet 3: Invalid lines that should be ignored (would otherwise inflate count)
    for _ in range(50):
        # Invalid status code
        f.write(f"2023-10-01T15:{random.randint(10,59)}:00 172.16.20.{random.randint(1,254)} LOGOUT 20\n")
    for _ in range(50):
        # Invalid timestamp
        f.write(f"2023-10-01T15:{random.randint(10,59)} 172.16.20.{random.randint(1,254)} LOGOUT 200\n")

    # Subnet 4: Not enough base count (<50)
    for _ in range(40):
        f.write(f"2023-10-01T10:{random.randint(10,59)}:00 192.168.100.{random.randint(1,254)} LOGIN 200\n")
    for _ in range(5):
        f.write(f"2023-10-01T11:{random.randint(10,59)}:00 192.168.100.{random.randint(1,254)} LOGIN 200\n")
EOF
    python3 /tmp/generate_logs.py

    chmod -R 777 /home/user
