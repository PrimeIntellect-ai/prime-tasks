#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/src
    cat << 'EOF' > /home/user/resource_usage.csv
2023-10-01T10:00:00Z,80,60
2023-10-01T10:05:00Z,90,92
2023-10-01T10:10:00Z,50,80
2023-10-01T10:15:00Z,85,84
EOF

    chmod -R 777 /home/user
