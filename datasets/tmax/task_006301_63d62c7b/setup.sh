#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/db

    cat << 'EOF' > /home/user/generate_wal.py
import struct

def write_record(f, txid, payload_bytes):
    f.write(struct.pack('<I', txid))
    f.write(struct.pack('<I', len(payload_bytes)))
    f.write(payload_bytes)

with open('/home/user/db/transaction.wal', 'wb') as f:
    # Valid record 1
    write_record(f, 1, b'{"value": 150}')
    # Valid record 2
    write_record(f, 2, b'{"value": 250}')
    # Corrupted record 3 (Invalid UTF-8 sequence \xff)
    write_record(f, 3, b'{"value": 350, "data": "\xff\xfe"}')
    # Valid record 4
    write_record(f, 4, b'{"value": 100}')
EOF
    python3 /home/user/generate_wal.py
    rm /home/user/generate_wal.py

    cat << 'EOF' > /home/user/recovery.py
import struct
import sys
# Bug 1: Using a non-existent/unnecessary third-party library that causes a crash
try:
    import ujson as json
except ImportError:
    import json # fallback

def recover_wal(filepath):
    total_value = 0
    with open(filepath, 'rb') as f:
        while True:
            header = f.read(8)
            if not header or len(header) < 8:
                break
            txid, length = struct.unpack('<II', header)
            payload_bytes = f.read(length)

            # Bug 2: Strict decoding crashes on invalid bytes
            payload_str = payload_bytes.decode('utf-8')
            data = json.loads(payload_str)

            if 'value' in data:
                total_value += data['value']

    print(f"Recovery complete. Total: {total_value}")

if __name__ == "__main__":
    recover_wal('/home/user/db/transaction.wal')
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
