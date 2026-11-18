#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/quota_report.txt
SYSTEM STORAGE REPORT - GENERATED 2023-10-25
=========================================
DIR /opt/app/frontend USAGE 1200 QUOTA 2000
DIR /opt/app/backend USAGE 4800 QUOTA 5000
IGNORE THIS LINE
DIR /opt/app/database USAGE 10000 QUOTA 15000
DIR /opt/app/cache USAGE 850 QUOTA 1000
DIR /opt/app/logs USAGE 500 QUOTA 800
DIR /tmp/scratch USAGE 10 QUOTA 100
=========================================
EOF

    cat << 'EOF' > /home/user/update_dirs.txt
/opt/app/backend
/opt/app/cache
/opt/app/frontend
/opt/app/logs
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
