#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip qemu-utils
    pip3 install pytest

    mkdir -p /home/user/nodes/node1
    mkdir -p /home/user/nodes/node2
    mkdir -p /home/user/nodes/node3

    for i in 1 2 3; do
        qemu-img create -f qcow2 /home/user/nodes/node$i/disk.qcow2 5M
    done

    cat << 'EOF' > /home/user/admin_groups.txt
wheel:alice,bob,charlie
deployers:zane,xena,yusuf
admins:root,admin
EOF

    cat << 'EOF' > /home/user/update_payload.py
import sys
print("Application running OK")
sys.exit(0)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
