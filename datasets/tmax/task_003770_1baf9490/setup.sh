#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /home/user/config_repo/web
    mkdir -p /home/user/config_repo/db
    mkdir -p /home/user/config_repo/net/internal

    echo -n -e "port=8080\nhost=localhost\nenv=production" | iconv -f UTF-8 -t UTF-16LE > /home/user/config_repo/web/app_settings.conf
    echo -n -e "db_type=postgres\ndb_port=5432" | iconv -f UTF-8 -t UTF-16LE > /home/user/config_repo/db/db_config.conf
    echo -n -e "ip=192.168.1.1\nsubnet=255.255.255.0" | iconv -f UTF-8 -t UTF-16LE > /home/user/config_repo/net/internal/network.conf

    cat << 'EOF' > /home/user/audit.log
[RECORD]
ID: 101
File: app_settings.conf
Status: CHANGED
[END]
[RECORD]
ID: 102
File: db_config.conf
Status: UNCHANGED
[END]
[RECORD]
ID: 103
File: network.conf
Status: CHANGED
[END]
[RECORD]
ID: 104
File: missing.conf
Status: CHANGED
[END]
EOF

    cat << 'EOF' > /home/user/expected_summary.txt
--- app_settings.conf ---
port=8080
host=localhost
env=production
--- network.conf ---
ip=192.168.1.1
subnet=255.255.255.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
