#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os

data = [
    ("id", "value", "category"),
    ("1", "12.34567", "A"),
    ("2", "NaN", "B"),
    ("3", "-9.87654", "A"),
    ("4", "100.0001", "C"),
    ("5", "err_5.4", "A"),
    ("6", "45.6789", "B"),
    ("7", "-105.0", "B"),
    ("8", "0.00000", "C"),
    ("9", "inf", "C"),
    ("10", "3.14159", "C"),
    ("11", "50.0", "A")
]

os.makedirs("/home/user", exist_ok=True)
with open("/home/user/raw_measurements.csv", "w") as f:
    for row in data:
        f.write(f"{row[0]},{row[1]},{row[2]}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
