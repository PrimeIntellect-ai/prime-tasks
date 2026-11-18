#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/wal_data
    cd /home/user/wal_data

    python3 -c '
import struct
import os

def make_wal(filename, seq, payload_size, actual_payload_size, magic=b"WAL!"):
    with open(filename, "wb") as f:
        f.write(magic)
        f.write(struct.pack("<I", seq))
        f.write(struct.pack("<Q", payload_size))
        f.write(b"x" * actual_payload_size)

make_wal("01.wal", 1, 100, 100)
make_wal("02.wal", 2, 250, 250)
make_wal("03.wal", 3, 500, 284)
make_wal("04.wal", 4, 100, 104)
make_wal("05.wal", 5, 0, 0)
make_wal("06.wal", 6, 50, 50, b"BAD!")
make_wal("07.wal", 9999, 10, 10)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
