#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip gcc tar
    pip3 install pytest

    mkdir -p /home/user/repo
    mkdir -p /home/user/unpacked

    python3 -c "
import os, random
random.seed(42)
with open('/home/user/repo/blob1.bin', 'wb') as f:
    f.write(bytes(random.getrandbits(8) for _ in range(3500)))
with open('/home/user/repo/data_payload.bin', 'wb') as f:
    f.write(bytes(random.getrandbits(8) for _ in range(2048)))
"

    mkdir -p /home/user/repo/configs
    echo "system_mode=production" > /home/user/repo/configs/sys.conf

    cd /home/user/repo
    zip nested.zip configs/sys.conf data_payload.bin
    tar -czf bundle.tar.gz blob1.bin nested.zip

    rm -rf blob1.bin configs data_payload.bin nested.zip

    cat << 'EOF' > /home/user/raw_manifest.txt
# Artifact list for current build
   blob1.bin   

configs/sys.conf   # Main configuration
    data_payload.bin
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/repo /home/user/raw_manifest.txt /home/user/unpacked
    chmod -R 777 /home/user
