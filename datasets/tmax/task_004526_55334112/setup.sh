#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import zipfile

os.makedirs('/home/user/incoming', exist_ok=True)
os.makedirs('/home/user/artifacts/raw', exist_ok=True)
os.makedirs('/home/user/artifacts/links', exist_ok=True)

zip_path = '/home/user/incoming/payload.zip'
with zipfile.ZipFile(zip_path, 'w') as zf:
    zf.writestr('firmware_v1.bin', b'\x00\x01\x02\x03')
    zf.writestr('configs/settings.dat', b'config_data=123')
    zf.writestr('assets/logo.png', b'PNG...')
    zf.writestr('../escape1.bin', b'malicious payload 1')
    zf.writestr('configs/../../escape2.bin', b'malicious payload 2')
    zf.writestr('/absolute/path/escape3.bin', b'malicious payload 3')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chown -R user:user /home/user/incoming
    chown -R user:user /home/user/artifacts
    chmod -R 777 /home/user
