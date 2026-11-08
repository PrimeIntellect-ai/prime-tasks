#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip
    pip3 install pytest

    # Create the setup script
    cat << 'EOF' > /tmp/setup.py
import os
import struct
import tarfile

os.makedirs('/home/user', exist_ok=True)
os.chdir('/home/user')

# Create binary files
# FileA: valid
with open('fileA.bin', 'wb') as f:
    f.write(b'ARTF')
    f.write(b'libnetwork'.ljust(16, b'\x00'))
    f.write(struct.pack('<I', 2))
    f.write(b'payload_data_a')

# FileB: valid
with open('fileB.bin', 'wb') as f:
    f.write(b'ARTF')
    f.write(b'core_engine'.ljust(16, b'\x00'))
    f.write(struct.pack('<I', 15))
    f.write(b'payload_data_b')

# FileC: invalid magic
with open('fileC.bin', 'wb') as f:
    f.write(b'JUNK')
    f.write(b'bad_artifact'.ljust(16, b'\x00'))
    f.write(struct.pack('<I', 99))
    f.write(b'payload_data_c')

# Archive them
with tarfile.open('artifacts.tar.gz', 'w:gz') as tar:
    tar.add('fileA.bin')
    tar.add('fileB.bin')
    tar.add('fileC.bin')

# Cleanup original files
os.remove('fileA.bin')
os.remove('fileB.bin')
os.remove('fileC.bin')
EOF

    # Execute the setup script
    python3 /tmp/setup.py
    rm /tmp/setup.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
