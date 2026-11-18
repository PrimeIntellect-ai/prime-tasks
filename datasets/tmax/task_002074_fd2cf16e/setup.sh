#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go tar gzip coreutils
    pip3 install pytest

    mkdir -p /home/user/raw_configs
    mkdir -p /home/user/configs
    mkdir -p /home/user/processed_configs

    cat << 'EOF' > /home/user/raw_configs/conf_a12.json
{
  "service": "frontend",
  "version": "1.0.4",
  "debug_token": "xyz987_secret",
  "port": 3000,
  "features": ["auth", "dashboard"]
}
EOF

    cat << 'EOF' > /home/user/raw_configs/db_backup_old.json
{
  "service": "database",
  "version": "13.2",
  "debug_token": "admin_bypass_xyz",
  "max_connections": 100
}
EOF

    cat << 'EOF' > /home/user/raw_configs/cache_main.json
{
  "service": "redis_cache",
  "version": "6.2.0",
  "max_memory": "4gb"
}
EOF

    cd /home/user/raw_configs
    tar -czf configs.tar.gz *.json
    rm *.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
