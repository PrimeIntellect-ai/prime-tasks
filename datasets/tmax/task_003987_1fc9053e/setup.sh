#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import struct
import time

def create_cfgpack(path, entries):
    with open(path, 'wb') as f:
        f.write(b'CFGP')
        f.write(struct.pack('<H', len(entries)))
        for name, data in entries:
            name_bytes = name.encode('utf-8')
            f.write(struct.pack('<H', len(name_bytes)))
            f.write(name_bytes)
            f.write(struct.pack('<I', len(data)))
            f.write(data)

os.makedirs('/home/user/incoming/subdir', exist_ok=True)

create_cfgpack('/home/user/incoming/valid.cfgpack', [
    ('app/config.json', b'{"debug": true}'),
    ('app/db.conf', b'host=localhost')
])

create_cfgpack('/home/user/incoming/evil.cfgpack', [
    ('app/config.json', b'{}'),
    ('../../etc/passwd', b'fake_data')
])

create_cfgpack('/home/user/incoming/subdir/absolute.cfgpack', [
    ('/root/.ssh/id_rsa', b'private_key')
])

create_cfgpack('/home/user/incoming/old.cfgpack', [
    ('app/config.json', b'old')
])

# Set old.cfgpack to 48 hours ago
old_time = time.time() - (48 * 3600)
os.utime('/home/user/incoming/old.cfgpack', (old_time, old_time))
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
