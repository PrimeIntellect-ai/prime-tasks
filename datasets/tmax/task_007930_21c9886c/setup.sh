#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/old_app1.log
[2023-01-01 10:00:00] [INFO] [10.0.0.1] Startup complete
[2023-01-01 10:05:00] [ERROR] [192.168.10.42] Database connection failed
[2023-01-01 10:10:00] [CRITICAL] [172.16.0.100] Out of memory
EOF

    cat << 'EOF' > /home/user/logs/old_app2.log
[2023-01-02 11:00:00] [WARNING] [10.0.0.5] High latency
[2023-01-02 11:05:00] [ERROR] [8.8.8.8] DNS resolution failed
EOF

    cat << 'EOF' > /home/user/logs/new_app1.log
[2024-01-01 10:00:00] [ERROR] [10.1.1.1] This should not be in the archive
EOF

    cat << 'EOF' > /home/user/logs/new_app2.log
[2024-01-01 10:00:00] [CRITICAL] [10.2.2.2] This should also not be in the archive
EOF

    touch -d "30 days ago" /home/user/logs/old_app1.log
    touch -d "30 days ago" /home/user/logs/old_app2.log
    touch -d "1 day ago" /home/user/logs/new_app1.log
    touch -d "1 day ago" /home/user/logs/new_app2.log

    chmod -R 777 /home/user
