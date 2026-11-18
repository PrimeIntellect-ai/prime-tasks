#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import struct
import random
import os

random.seed(42)
records = []
for i in range(10000):
    sid = random.randint(1, 20)
    ts = 1620000000 + i
    val = round(random.uniform(10.0, 100.0), 4)
    records.append((sid, ts, val))

csv_recs = records[::2]
bin_recs = records[1::2]

with open('/home/user/data.csv', 'w') as f:
    for r in csv_recs:
        f.write(f"{r[0]},{r[1]},{r[2]:.4f}\n")

with open('/home/user/data.bin', 'wb') as f:
    for r in bin_recs:
        f.write(struct.pack('<iqd', r[0], r[1], r[2]))
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
