#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/repo/binaries
    mkdir -p /home/user/repo/staging
    mkdir -p /home/user/backup

    # Create dummy binaries
    echo "binary data 1" > /home/user/repo/binaries/deadbeef.bin
    echo "binary data 2" > /home/user/repo/binaries/cafebabe.bin
    echo "binary data 3" > /home/user/repo/binaries/8badf00d.bin

    # Create the mapping CSV
    cat << 'EOF' > /home/user/repo/mapping.csv
deadbeef.bin,core-v1.2.0.bin
cafebabe.bin,core-v1.2.1.bin
8badf00d.bin,utils-v0.9.bin
EOF

    # Create a dummy initial snapshot
    mkdir -p /tmp/dummy_base
    echo "base" > /tmp/dummy_base/base.bin
    tar -g /home/user/backup/snapshot.snar -czf /home/user/backup/base.tar.gz -C /tmp/dummy_base .
    rm -rf /tmp/dummy_base

    chown -R user:user /home/user/repo /home/user/backup
    chmod -R 777 /home/user
