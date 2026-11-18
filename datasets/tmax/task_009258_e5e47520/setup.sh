#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import random
import struct

# 1. Create disk_dump.bin
dump_size = 1024 * 1024 # 1 MB
random.seed(42)
dump_data = bytearray(os.urandom(dump_size))

log_magic = b'LOG\x00'
rec1 = struct.pack('>HH', 0, 4) + b'JUNK'
rec2 = struct.pack('>HH', 1, 22) + b'FLAG{R3C0V3R3D_P4RS3D}'
terminator = b'\xff\xff\xff\xff'

binary_log = log_magic + rec1 + rec2 + terminator

# Inject into dump
inject_offset = 500000
dump_data[inject_offset:inject_offset+len(binary_log)] = binary_log

with open('/home/user/disk_dump.bin', 'wb') as f:
    f.write(dump_data)

# 2. Create parser.py
parser_code = """#!/usr/bin/env python3
import sys
import struct

def parse_log(filepath):
    with open(filepath, 'rb') as f:
        magic = f.read(4)
        if magic != b'LOG\\x00':
            print("Invalid magic signature")
            sys.exit(1)

        while True:
            header = f.read(4)
            if header == b'\\xff\\xff\\xff\\xff':
                break
            if len(header) < 4:
                print("Unexpected EOF")
                break

            version, length = struct.unpack('>HH', header)

            # Application logic that crashes on version 0
            processing_factor = 100 // version

            payload = f.read(length)
            if version > 0:
                print(payload.decode('utf-8'))

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: parser.py <file>")
        sys.exit(1)
    parse_log(sys.argv[1])
"""

with open('/home/user/parser.py', 'w') as f:
    f.write(parser_code)

os.chmod('/home/user/parser.py', 0o755)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
