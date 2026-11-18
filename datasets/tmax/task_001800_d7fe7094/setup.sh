#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq parallel
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_configs/alpha
    mkdir -p /home/user/raw_configs/beta
    mkdir -p /home/user/raw_configs/gamma
    mkdir -p /home/user/raw_configs/delta
    mkdir -p /home/user/pipeline
    mkdir -p /home/user/output
    mkdir -p /home/user/processed_configs

    cat << 'EOF' > /home/user/raw_configs/alpha/config.txt
DB_HOST=10.0.0.1
DB_PORT=5432
CACHE_SIZE=1024
MAX_RETRIES=3
EOF

    cat << 'EOF' > /home/user/raw_configs/beta/config.txt
DB_HOST=10.0.0.2
DB_PORT=5432
CACHE_SIZE=2048
TIMEOUT=30
EOF

    cat << 'EOF' > /home/user/raw_configs/gamma/config.json
{
  "DB_HOST": "10.0.0.3",
  "DB_PORT": "5432",
  "MAX_RETRIES": "5",
  "TIMEOUT": "60"
}
EOF

    cat << 'EOF' > /home/user/raw_configs/delta/config.txt
DB_HOST=10.0.0.4
ERROR_STATE=1
DB_PORT=5432
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
