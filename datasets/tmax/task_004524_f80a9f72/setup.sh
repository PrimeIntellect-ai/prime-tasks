#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/expected_users.txt
user
db_admin
app_worker
cache_daemon
EOF
    chmod 644 /home/user/expected_users.txt

    chmod -R 777 /home/user
