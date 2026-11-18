#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/raw_data_staging
    cd /home/user/raw_data_staging

    cat << 'EOF' > generate.py
import struct
import os

records = [
    ("rec_001", 104, 1680000000, [1.1111, 2.2222, 3.3333, 4.4444, 5.5555, 6.6666, 7.7777, 8.8888, 9.9999, 10.0000]),
    ("rec_002", 205, 1680003600, [0.0, -1.5, 3.1415, 2.7182, 42.0, 7.0, 8.0, 9.0, 10.1234, -5.5555]),
    ("rec_003", 99, 1680007200, [100.1, 200.2, 300.3, 400.4, 500.5, 600.6, 700.7, 800.8, 900.9, 1000.1]),
]

for name, sensor_id, ts, floats in records:
    # Write .dat
    with open(f"{name}.dat", "wb") as f:
        f.write(b"SNSR")
        f.write(struct.pack("<I", sensor_id))
        f.write(struct.pack("<I", ts))
        for val in floats:
            f.write(struct.pack("<f", val))

    # Write .txt
    with open(f"{name}.txt", "w") as f:
        f.write(f"Notes for {name}\n")

EOF

    python3 generate.py
    tar -czf /home/user/raw_data.tar.gz rec_*.dat rec_*.txt
    cd /
    rm -rf /home/user/raw_data_staging

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
