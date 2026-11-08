#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/validator.py
import sys

def validate(filepath):
    try:
        with open(filepath, 'rb') as f:
            data = f.read()
    except Exception:
        return False

    if len(data) < 11:
        return False

    if data[0:4] != b'MOBI':
        return False

    version = int.from_bytes(data[4:6], 'little')
    if version != 1:
        return False

    payload_size = int.from_bytes(data[6:10], 'little')
    if len(data) != 10 + payload_size + 1:
        return False

    payload = data[10:10+payload_size]
    expected_checksum = data[-1]

    actual_checksum = 0
    for byte in payload:
        actual_checksum ^= byte

    return actual_checksum == expected_checksum

if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(1)
    if validate(sys.argv[1]):
        sys.exit(0)
    else:
        sys.exit(1)
EOF

    python3 -c "
with open('/home/user/valid.bin', 'wb') as f:
    f.write(b'\x4D\x4F\x42\x49\x01\x00\x03\x00\x00\x00\x41\x42\x43\x40')
with open('/home/user/invalid.bin', 'wb') as f:
    f.write(b'\x4D\x4F\x42\x49\x01\x00\x03\x00\x00\x00\x41\x42\x43\x41')
"

    chmod -R 777 /home/user
