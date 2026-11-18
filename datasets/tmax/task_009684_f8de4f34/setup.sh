#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.txt
2023-11-01T08:14:22Z | 192.168.1.100 | {"auth_fail": 2, "db_timeout": 0, "rate_limit": 1}
2023-11-01T08:45:10Z | 10.0.0.5      | {"auth_fail": 1, "db_timeout": 1, "rate_limit": 0}
2023-11-01T08:59:59Z | 192.168.1.101 | {"auth_fail": 0, "db_timeout": 0, "rate_limit": 1}
2023-11-01T09:05:00Z | 10.0.0.5      | {"auth_fail": 0, "db_timeout": 5, "rate_limit": 0}
2023-11-01T09:22:30Z | 192.168.1.100 | {"auth_fail": 0, "db_timeout": 2, "rate_limit": 0}
2023-11-01T10:15:00Z | 172.16.0.4    | {"auth_fail": 5, "db_timeout": 0, "rate_limit": 4}
EOF

    chmod -R 777 /home/user
