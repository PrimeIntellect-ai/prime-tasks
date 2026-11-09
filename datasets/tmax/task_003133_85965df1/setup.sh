#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        qemu-system-x86 \
        e2fsprogs \
        tar \
        gzip

    pip3 install pytest

    mkdir -p /home/user/manifests
    touch /home/user/manifests/app.yaml

    cat << 'EOF' > /home/user/connection.log
debug1: Connecting to 10.0.0.5 [10.0.0.5] port 22.
debug1: Connection established.
debug1: receive packet: type 51
debug1: Connecting to 192.168.1.10 [192.168.1.10] port 22.
debug1: receive packet: type 52
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
