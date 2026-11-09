#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming
    mkdir -p /home/user/outgoing

    cat << 'EOF' > /tmp/setup.py
import os
import tarfile
import io
import shutil

os.makedirs('/home/user/incoming', exist_ok=True)
os.makedirs('/home/user/outgoing', exist_ok=True)
os.makedirs('/tmp/setup_repo/release/artifacts', exist_ok=True)

with open('/tmp/setup_repo/release/metadata.txt', 'w') as f:
    f.write("Release Version: ${VERSION}\nDate: ${BUILD_DATE}\nTarget: ${ENVIRONMENT}\n")

with open('/tmp/setup_repo/release/artifacts/bin1.dat', 'wb') as f:
    f.write(b'\x00\x01\x02\x03\x04')

with open('/tmp/setup_repo/release/artifacts/bin1.meta', 'w') as f:
    f.write("Binary: bin1\nVersion: ${VERSION}\nEnv: ${ENVIRONMENT}\n")

tar_stream = io.BytesIO()
with tarfile.open(fileobj=tar_stream, mode='w:gz') as tar:
    tar.add('/tmp/setup_repo/release', arcname='release')

tar_data = tar_stream.getvalue()
obfuscated_data = bytes([b ^ 0x5A for b in tar_data])

with open('/home/user/incoming/repository.dat', 'wb') as f:
    f.write(obfuscated_data)

shutil.rmtree('/tmp/setup_repo')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
