#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import os

os.makedirs('/home/user/artifacts/raw/group1', exist_ok=True)
os.makedirs('/home/user/artifacts/raw/group2/sub', exist_ok=True)

with open('/home/user/artifacts/raw/group1/fileA.blob', 'wb') as f:
    f.write(b'\x05\x41\x03\x42\x00\x00')

with open('/home/user/artifacts/raw/group2/sub/fileB.blob', 'wb') as f:
    f.write(b'\x02\x58\x02\x59\x00\x00')

with open('/home/user/artifacts/raw/group1/fileC.blob', 'wb') as f:
    f.write(b'\x01\x5A\x00\x00')
"

    chown -R user:user /home/user/artifacts
    chmod -R 777 /home/user
