#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user

    # Generate the binary file
    python3 -c '
import struct

# Data records: string_id, en, fr, de, es, ja
records = [
    (1, 50, 55, 60, 55, 40),
    (2, 52, 60, 62, 58, 42),
    (3, 48, 52, 58, 50, 45),
    (4, 55, 60, 65, 60, 48),
    (5, 60, 150, 70, 65, 110),
    (6, 40, 45, 50, 48, 40),
    (7, 45, 50, 55, 50, 42),
    (8, 48, 55, 58, 52, 45),
    (9, 50, 58, 60, 55, 48),
    (10, 55, 60, 105, 60, 50)
]

with open("/home/user/telemetry.bin", "wb") as f:
    for rec in records:
        f.write(struct.pack("<iiiiii", *rec))
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
