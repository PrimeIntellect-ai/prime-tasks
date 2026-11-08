#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/metrics_1.csv
timestamp,cpu_usage,memory_mb,network_tx_kb
2023-10-01T10:00:00Z,20.0,1024,500
2023-10-01T11:00:00Z,22.0,1024,520
EOF

    cat << 'EOF' > /home/user/data/metrics_2.csv
timestamp,cpu_usage,memory_mb,network_tx_kb
2023-10-02T10:00:00Z,21.0,1024,500
2023-10-02T11:00:00Z,19.0,1024,510
EOF

    cat << 'EOF' > /home/user/data/metrics_3.csv
timestamp,cpu_usage,memory_mb,network_tx_kb
2023-10-03T10:00:00Z,20.0,1024,500
2023-10-03T11:00:00Z,20.0,1024,510
EOF

    cat << 'EOF' > /home/user/data/metrics_4.csv
timestamp,cpu_usage,memory_mb,network_tx_kb
2023-10-04T10:00:00Z,40.0,2048,1500
2023-10-04T11:00:00Z,45.0,2048,1520
EOF

    cat << 'EOF' > /home/user/data/metrics_5.csv
timestamp,cpu_usage,memory_mb,network_tx_kb
2023-10-05T10:00:00Z,42.0,2048,1500
2023-10-05T11:00:00Z,42.0,2048,1520
EOF

    chmod -R 777 /home/user
