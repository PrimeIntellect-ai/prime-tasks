#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_logs

    cat << 'EOF' > /home/user/app_logs/log_old.txt
[INFO] System started
[TRACE] Loading modules
[ERROR] Module A failed
[TRACE] Retrying
EOF

    touch -t 202301010000 /home/user/app_logs/log_old.txt
    touch -t 202301020000 /home/user/last_run.stamp

    cat << 'EOF' > /home/user/app_logs/log_recent1.txt
[INFO] System running
[TRACE] Checking memory
[ERROR] Memory limit exceeded
[TRACE] Garbage collection
[ERROR] GC failed
EOF

    cat << 'EOF' > /home/user/app_logs/log_recent2.txt
[TRACE] User login attempt
[INFO] User logged in
[TRACE] Accessing dashboard
EOF

    chmod -R 777 /home/user
