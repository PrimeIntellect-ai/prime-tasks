#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip
    pip3 install pytest

    mkdir -p /home/user/raw_logs

    cat << 'EOF' > /home/user/raw_logs/server_alpha.log
[INFO] Server started
[WARNING] High memory usage
[CRITICAL] Database connection lost
[INFO] Retrying connection
EOF

    cat << 'EOF' > /home/user/raw_logs/server_beta.log
[INFO] Beta node online
[CRITICAL] Disk space critically low on /dev/sda1
[INFO] Cleaning up temp files
EOF

    cat << 'EOF' > /home/user/raw_logs/server_gamma.log
[INFO] Gamma node synced
[WARNING] Network latency detected
[CRITICAL] Unhandled exception in worker thread
EOF

    gzip /home/user/raw_logs/*.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
