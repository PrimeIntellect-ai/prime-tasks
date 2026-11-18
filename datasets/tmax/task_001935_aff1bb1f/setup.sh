#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import struct
import os

def create_frame(payload, bad_checksum=False):
    payload_bytes = payload.encode('ascii')
    length = len(payload_bytes)
    checksum = 0
    for b in payload_bytes:
        checksum ^= b
    if bad_checksum:
        checksum ^= 0x01
    return b'\xBE\xEF' + struct.pack('<H', length) + payload_bytes + bytes([checksum])

frames = [
    b'randomgarbage123\xBE\xEF\x00\x00',
    create_frame("EVENT: START"),
    create_frame("USER: root API_KEY=A1b2C3d4E5f6G7h8 action=login"),
    create_frame("USER: guest API_KEY=FakeKey123badche bad_checksum", bad_checksum=True),
    b'moregarbage\xBE\xEF\x00',
    create_frame("API_KEY=1111222233334444"),
    create_frame("CONNECTION TERMINATED")
]

with open('/home/user/suspect_data.dat', 'wb') as f:
    for item in frames:
        f.write(item)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
