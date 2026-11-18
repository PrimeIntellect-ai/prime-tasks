#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pyarrow

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_logs.csv
timestamp,server_id,log_message
2023-01-01T10:00:00Z,srv-01,INFO: System started
2023-01-01T10:05:00Z,srv-01,ERROR: Database connection timeout
2023-01-01T10:06:00Z,srv-02,ERROR: Access denied for user admin
2023-01-01T10:10:00Z,srv-01,ERROR: Connection reset by peer
2023-01-01T10:15:00Z,srv-03,ERROR: Fatal crash in module X
2023-01-01T10:20:00Z,srv-02,ERROR: Timeout waiting for lock
2023-01-01T10:25:00Z,srv-01,ERROR: Database connection timeout
2023-01-01T10:30:00Z,srv-04,INFO: All systems operational
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
