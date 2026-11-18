#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/servers.csv
host,cpu,mem,disk
server-001,45.2,55.1,30.0
server-002,82.1,25.3,58.9
server-003,90.0,15.0,70.0
server-004,84.5,21.0,61.0
server-005,10.0,90.0,10.0
server-006,86.0,19.0,59.0
server-007,50.0,50.0,50.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
