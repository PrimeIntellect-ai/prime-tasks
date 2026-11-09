#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip perl ruby
    pip3 install pytest

    mkdir -p /home/user/sys_mock/eno1
    mkdir -p /home/user/sys_mock/enp2s0
    mkdir -p /home/user/sys_mock/enp3s0f1
    mkdir -p /home/user/sys_mock/enx00112233

    echo "00:1a:2b:3c:4d:5e" > /home/user/sys_mock/eno1/address
    echo "52:54:00:ab:cd:ef" > /home/user/sys_mock/enp2s0/address
    echo "a1:b2:c3:d4:e5:f6" > /home/user/sys_mock/enp3s0f1/address
    echo "00:11:22:33:44:55" > /home/user/sys_mock/enx00112233/address

    cat << 'EOF' > /home/user/inventory_dump.log
Host: server-rack-04-node-12
Date: 2023-10-25
Hardware: Dell R640
MAC: 00:1A:2B:3C:4D:5E | ROLE: management
MAC: 00:11:22:33:44:55 | ROLE: frontend
MAC: A1:B2:C3:D4:E5:F6 | ROLE: storage_backend
MAC: 52:54:00:AB:CD:EF | ROLE: backup
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
