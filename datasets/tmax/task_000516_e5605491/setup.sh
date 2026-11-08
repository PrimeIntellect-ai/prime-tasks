#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/baseline.txt
interface vlan 100
ip address 192.168.1.1 255.255.255.0
no shutdown
description "Main Office Vlan"
EOF

    cat << 'EOF' > /home/user/changes.log
2023-10-01T10:00:00Z | Interface Vlan 100; IP Address 192.168.1.1 255.255.255.0; No Shutdown; Description "Main Office Vlan"
MISSING | interface vlan 100, ip address 192.168.1.1 255.255.255.0, shutdown, description "Main Office Vlan"
MISSING | int vlan 100 ip 192.168.1.1 255.255.255.0
2023-10-01T10:20:00Z | Interface Vlan 100; IP Address 192.168.1.2 255.255.255.0; No Shutdown; Description "Main Office Vlan"
EOF

    chmod -R 777 /home/user
