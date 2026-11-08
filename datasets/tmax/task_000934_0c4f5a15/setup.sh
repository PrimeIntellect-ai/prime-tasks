#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_logs.txt
2023-11-01T12:00:00Z|user_alpha|System is booting up, system is ready!
2023-11-01T12:01:00Z|user_beta|Warning: low memory. Warning: high CPU!
2023-11-01T12:02:00Z|user_alpha|Ready for processing.
2023-11-01T12:03:00Z|user_gamma|ERROR 404 - Not found. ERROR 500.
2023-11-01T12:04:00Z|user_beta|Memory freed.
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
