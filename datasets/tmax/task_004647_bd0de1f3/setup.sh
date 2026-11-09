#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os

os.makedirs("/home/user/logs/", exist_ok=True)
os.makedirs("/home/user/archive/", exist_ok=True)

# File 1: serviceA.log - 15,000 lines, [IGNORE] on every 5th line
with open("/home/user/logs/serviceA.log", "w") as f:
    for i in range(1, 15001):
        if i % 5 == 0:
            f.write(f"Line {i} [IGNORE] unnecessary trace data\n")
        else:
            f.write(f"Line {i} standard log output\n")

# File 2: serviceB.log - 8,000 lines (Should not be processed)
with open("/home/user/logs/serviceB.log", "w") as f:
    for i in range(1, 8001):
        f.write(f"Line {i} standard log output\n")

# File 3: serviceC.log - 25,000 lines, [IGNORE] on every 10th line
with open("/home/user/logs/serviceC.log", "w") as f:
    for i in range(1, 25001):
        if i % 10 == 0:
            f.write(f"Line {i} [IGNORE] unnecessary trace data\n")
        else:
            f.write(f"Line {i} standard log output\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
