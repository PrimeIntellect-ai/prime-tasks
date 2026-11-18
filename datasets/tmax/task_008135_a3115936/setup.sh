#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create setup script for initial state
    cat << 'EOF' > /tmp/setup.py
import os
import tarfile
import time

os.makedirs('/home/user/backups', exist_ok=True)
os.makedirs('/home/user/extracted/subdir', exist_ok=True)

os.makedirs('/tmp/pack/subdir', exist_ok=True)
with open('/tmp/pack/legit.txt', 'wb') as f:
    f.write("Café".encode('iso-8859-1'))
with open('/tmp/pack/evil.txt', 'w') as f:
    f.write("evil")
with open('/tmp/pack/subdir/old.txt', 'w') as f:
    f.write("Archive Old")
with open('/tmp/pack/subdir/new.txt', 'w') as f:
    f.write("Archive New")

os.utime('/tmp/pack/subdir/old.txt', (1700000000, 1700000000))
os.utime('/tmp/pack/subdir/new.txt', (1700000000, 1700000000))
os.utime('/tmp/pack/legit.txt', (1700000000, 1700000000))

with tarfile.open('/home/user/backups/data.tar', 'w') as tar:
    tar.add('/tmp/pack/legit.txt', arcname='legit.txt')
    tar.add('/tmp/pack/evil.txt', arcname='../evil.txt')
    tar.add('/tmp/pack/subdir/old.txt', arcname='subdir/old.txt')
    tar.add('/tmp/pack/subdir/new.txt', arcname='subdir/new.txt')

with open('/home/user/extracted/subdir/old.txt', 'w') as f:
    f.write("Original Old")
os.utime('/home/user/extracted/subdir/old.txt', (1800000000, 1800000000))

with open('/home/user/extracted/subdir/new.txt', 'w') as f:
    f.write("Original New")
os.utime('/home/user/extracted/subdir/new.txt', (1600000000, 1600000000))
EOF

    python3 /tmp/setup.py
    rm -rf /tmp/setup.py /tmp/pack

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
