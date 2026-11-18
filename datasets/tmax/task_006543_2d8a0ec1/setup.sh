#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import zlib
import struct

os.makedirs('/home/user/backups', exist_ok=True)

def create_cba(filepath, files):
    with open(filepath, 'wb') as f:
        f.write(b'CB')
        f.write(struct.pack('<I', len(files)))
        for filename, data in files:
            encoded_name = filename.encode('utf-8')
            compressed_data = zlib.compress(data)
            f.write(struct.pack('<H', len(encoded_name)))
            f.write(encoded_name)
            f.write(struct.pack('<I', len(compressed_data)))
            f.write(compressed_data)

files_to_pack = [
    ('valid_log.wal', b'WAL\x00 + some random WAL data for testing'),
    ('../../../home/user/malicious.sh', b'\x7fELF + malicious binary data here'),
    ('bin/system_tool', b'\x7fELF + valid binary data here'),
    ('random_notes.txt', b'Hello world, this is just a text file.'),
]

create_cba('/home/user/backups/daily.cba', files_to_pack)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
