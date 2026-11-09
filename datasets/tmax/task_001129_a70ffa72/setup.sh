#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo cron
    pip3 install pytest

    mkdir -p /home/user/migration_data
    mkdir -p /home/user/output
    mkdir -p /home/user/mnt/db-main
    mkdir -p /home/user/mnt/assets
    mkdir -p /home/user/mnt/cache

    cat << 'EOF' > /home/user/migration_data/legacy_services.json
[
  {"service_name": "db-main", "ip_address": "10.5.1.100", "status": "migrated", "nfs_export": "10.10.10.50:/vol/db-main"},
  {"service_name": "cache", "ip_address": "10.5.1.101", "status": "pending", "nfs_export": "10.10.10.50:/vol/cache"},
  {"service_name": "assets", "ip_address": "10.5.1.102", "status": "migrated", "nfs_export": "10.10.10.51:/vol/assets"}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
