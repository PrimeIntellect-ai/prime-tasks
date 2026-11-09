#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed grep bash
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create the raw dataset
    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_metrics.csv
timestamp,user_id,ip_address,cpu_usage
2023-10-12T08:15:00Z,U1001,10.0.4.12,45.2
2023-10-12T09:22:15Z,U1002,172.16.254.1,80.0
2023-10-12T14:35:22Z,U9482,192.168.1.45,84.5
2023-10-13T01:05:09Z,U1001,10.0.4.12,79.9
2023-10-13T23:59:59Z,U9999,8.8.8.8,12.0
EOF

    # Set permissions
    chmod -R 777 /home/user
