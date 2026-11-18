#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import struct
import random
import py_compile
import os

# 1. Create and compile the reader script
reader_path = "/home/user/reader.py"
with open(reader_path, "w") as f:
    f.write('def get_struct_format():\n    return "<I d f"\n')

py_compile.compile(reader_path, cfile="/home/user/reader.pyc")
os.remove(reader_path)

# 2. Generate corrupted dataset
records = []
random.seed(42)
for i in range(1000):
    uid = random.randint(10, 50)
    timestamp = 1600000000.0 + i
    # Normal latency: mean 50.0, std 10.0
    lat = random.gauss(50.0, 10.0)

    # Inject anomalies
    if i in [100, 250, 500, 750]:
        uid = 99
        lat = 150.0 + random.random()*10

    records.append((uid, timestamp, lat))

with open("/home/user/corrupted_metrics.dat", "wb") as f:
    for i, r in enumerate(records):
        data = struct.pack("<I d f", *r)
        f.write(data)
        # Inject corruption marker (0xDEADBEEF) and 4 garbage bytes
        if i % 50 == 0:
            f.write(struct.pack("<I", 0xDEADBEEF))
            f.write(b"GARB") # 4 bytes
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
