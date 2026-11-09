#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_config_logs.txt
2024-01-01T00:00:00 [INFO] Config change for app-db-primary | max_memory:1000 | workers:4
2024-01-01T01:00:00 [INFO] Config change for app-db-secondary | max_memory:2000 | workers:2
2024-01-01T02:00:00 [INFO] Config change for app-db-primary | max_memory:??? | workers:5
2024-01-01T03:00:00 [INFO] Config change for app-db-primary | max_memory:1200 | workers:5
2024-01-01T04:00:00 [INFO] Config change for app-db-primary | max_memory:1250 | workers:8
2024-01-01T05:00:00 [INFO] Config change for app-db-primary | max_memory:??? | workers:8
2024-01-01T06:00:00 [INFO] Config change for app-db-primary | max_memory:1400 | workers:10
EOF

    chmod -R 777 /home/user
