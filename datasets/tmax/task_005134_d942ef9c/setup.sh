#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming
    mkdir -p /home/user/hold
    mkdir -p /home/user/published

    cd /tmp
    echo -n "SIG-12345" > signature.bin
    echo -n "ELF-DATA" > binary.elf
    cat << 'EOF' > metadata.ini
[build]
version=1.0.42
arch=amd64
[runtime]
env=production
EOF

    tar -czf inner.tar.gz binary.elf metadata.ini
    zip release_1.zip inner.tar.gz signature.bin
    mv release_1.zip /home/user/hold/

    chmod -R 777 /home/user
