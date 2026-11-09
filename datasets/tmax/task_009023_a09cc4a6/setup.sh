#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/vm.conf
VM_NAME=production-db-01
VNC_DISPLAY=:12
MEMORY=4096M
VCPUS=4
EOF

    chmod -R 777 /home/user
