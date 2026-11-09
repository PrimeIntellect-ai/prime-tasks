#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data/zoneA
    mkdir -p /home/user/data/zoneB

    dd if=/dev/zero of=/home/user/data/zoneA/fileA1.dat bs=1M count=12
    dd if=/dev/zero of=/home/user/data/zoneA/fileA2.dat bs=1M count=5
    dd if=/dev/zero of=/home/user/data/zoneA/fileA3.dat bs=1M count=20
    dd if=/dev/zero of=/home/user/data/zoneB/fileB1.dat bs=1M count=8
    dd if=/dev/zero of=/home/user/data/zoneB/fileB2.dat bs=1M count=50

    cat << 'EOF' > /home/user/disk_reporter.py
#!/usr/bin/env python3
import sys
import os

try:
    dir_path = input("Enter directory path: ").strip()
    threshold = float(input("Enter size threshold in MB: ").strip())
    fmt = input("Output format (csv/json/text): ").strip()
except EOFError:
    sys.exit(1)

if not os.path.exists(dir_path):
    print("Directory not found")
    sys.exit(1)

results = []
for f in sorted(os.listdir(dir_path)):
    fpath = os.path.join(dir_path, f)
    if os.path.isfile(fpath):
        size_mb = os.path.getsize(fpath) / (1024 * 1024)
        if size_mb >= threshold:
            results.append((fpath, size_mb))

if fmt == "csv":
    print("File,SizeMB")
    for r in results:
        print(f"{r[0]},{r[1]:.2f}")
elif fmt == "text":
    for r in results:
        print(f"{r[0]} is {r[1]:.2f} MB")
EOF

    chmod +x /home/user/disk_reporter.py

    chmod -R 777 /home/user
