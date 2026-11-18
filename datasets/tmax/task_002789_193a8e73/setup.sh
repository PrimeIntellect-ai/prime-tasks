#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/network_events.csv
192.168.1.1,10.0.0.5,443,1610000000
192.168.1.2,10.0.0.6,80,1610000005
192.168.1.1,10.0.0.5,443,1610000010
192.168.1.1,10.0.0.5,80,1610000015
10.0.0.5,192.168.1.100,22,1610000020
192.168.1.2,10.0.0.6,80,1610000025
192.168.1.2,10.0.0.6,80,1610000030
10.0.0.5,192.168.1.100,22,1610000035
172.16.0.1,192.168.1.1,8080,1610000040
EOF

    chmod -R 777 /home/user
