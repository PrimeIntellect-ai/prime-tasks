#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import struct

records = [
    (105, b"Bob", 10.00, 0),
    (102, b"Charlie", 75.50, 1),
    (100, b"Alice", 50.25, 1),
    (101, b"Dave", 120.00, 2),
    (108, b"Eve", 200.75, 1)
]

with open("/home/user/transactions.dat", "wb") as f:
    for rec in records:
        f.write(struct.pack("<I16sfB", rec[0], rec[1], rec[2], rec[3]))
'

    chmod -R 777 /home/user
