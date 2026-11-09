#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import struct

def make_wal(filepath, operations, add_garbage=b""):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, 'wb') as f:
        f.write(b"DOCW")
        for op in operations:
            if op[0] == 0x01: # Insert
                text = op[1].encode('utf-8')
                encoded = bytes([b ^ 0xAA for b in text])
                f.write(struct.pack("<B H", 0x01, len(encoded)))
                f.write(encoded)
            elif op[0] == 0x02: # Delete
                f.write(struct.pack("<B H", 0x02, op[1]))
            elif op[0] == 0xFF: # Commit
                f.write(b"\xFF")
        f.write(add_garbage)

docs_raw = "/home/user/docs_raw"

make_wal(f"{docs_raw}/dir1/file1.wal", [
    (0x01, "abbbbccc"),
    (0xFF, None)
], b"trailing_garbage_that_should_be_ignored")

make_wal(f"{docs_raw}/dir2/file2.wal", [
    (0x01, "Hellooooo World!"),
    (0x02, 7),
    (0x01, "o Universe"),
    (0xFF, None)
])

make_wal(f"{docs_raw}/file3.wal", [
    (0x01, "A" * 256),
    (0xFF, None)
], b"\x01\x05\x00extra")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
