#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create filter.conf
    echo "TARGET_VERSION=1.4.2" > /home/user/filter.conf

    # Generate repo.bin using python script
    cat << 'EOF' > /tmp/gen_repo.py
import struct
import json

def write_record(f, rec_type, payload):
    f.write(struct.pack('<B', rec_type))
    f.write(struct.pack('<I', len(payload)))
    f.write(payload)

with open('/home/user/repo.bin', 'wb') as f:
    f.write(b'ARTF')

    # Record 1: matching JSON
    p1 = json.dumps({"artifact_name": "core-lib", "version": "1.4.2"}).encode('utf-8')
    write_record(f, 0x01, p1)

    # Record 2: binary data
    write_record(f, 0x02, b'\x00\xff\x10\x20\x30' * 10)

    # Record 3: non-matching JSON
    p3 = json.dumps({"artifact_name": "utils-pkg", "version": "1.5.0"}).encode('utf-8')
    write_record(f, 0x01, p3)

    # Record 4: matching JSON
    p4 = json.dumps({"artifact_name": "net-tools", "version": "1.4.2"}).encode('utf-8')
    write_record(f, 0x01, p4)

    # Record 5: binary data
    write_record(f, 0x02, b'\xaa\xbb\xcc')
EOF

    python3 /tmp/gen_repo.py

    # Set permissions
    chmod -R 777 /home/user
