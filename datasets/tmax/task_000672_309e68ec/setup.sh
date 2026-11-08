#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/extracted_configs

    cat << 'EOF' > /tmp/setup.py
import struct
with open('/home/user/configs.pkg', 'wb') as f:
    f.write(bytes([3])) # N

    # File 1
    path = b"app.csv"
    payload = b"env,production"
    f.write(bytes([len(path)]))
    f.write(path)
    f.write(struct.pack('<I', len(payload)))
    f.write(payload)

    # File 2
    path = b"../pwned_sys.csv"
    payload = b"root,hello"
    f.write(bytes([len(path)]))
    f.write(path)
    f.write(struct.pack('<I', len(payload)))
    f.write(payload)

    # File 3
    path = b"db/config.csv"
    payload = b"port,5432"
    f.write(bytes([len(path)]))
    f.write(path)
    f.write(struct.pack('<I', len(payload)))
    f.write(payload)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
