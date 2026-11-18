#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create task directories and files
    python3 -c "
import os

artifacts_dir = '/home/user/artifacts'
os.makedirs(artifacts_dir, exist_ok=True)

# Generate metadata.txt (UTF-16LE)
with open(os.path.join(artifacts_dir, 'metadata.txt'), 'wb') as f:
    f.write('Artifact Batch 42 - Active Stream'.encode('utf-16le'))

# Generate raw_data.bin
data = (b'\x00' * 300) + (b'\xab' * 50) + (b'\x01' * 1) + (b'\xff' * 255)
with open(os.path.join(artifacts_dir, 'raw_data.bin'), 'wb') as f:
    f.write(data)
"

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
