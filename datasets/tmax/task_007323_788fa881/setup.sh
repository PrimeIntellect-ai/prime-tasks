#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        cargo \
        rustc \
        gawk \
        sed \
        findutils \
        coreutils

    pip3 install pytest

    mkdir -p /home/user/raw_logs

    echo "1700000000" > /home/user/last_run.txt

    cat << 'EOF' > /home/user/raw_logs/system_old.log
INFO: Boot sequence initiated.
CRITICAL: Thermal threshold exceeded on CPU0.
WARN: Dropped 5 packets.
EOF
    touch -d @1690000000 /home/user/raw_logs/system_old.log

    cat << 'EOF' > /home/user/raw_logs/app_new.log
DEBUG: Starting app.
CRITICAL: Database connection lost.
INFO: Retrying...
CRITICAL: Out of memory.
EOF
    touch -d @1700005000 /home/user/raw_logs/app_new.log

    cat << 'EOF' > /home/user/raw_logs/auth_new.log
INFO: User admin logged in.
WARN: Invalid password for root.
CRITICAL: Multiple failed login attempts detected.
EOF
    touch -d @1700010000 /home/user/raw_logs/auth_new.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
