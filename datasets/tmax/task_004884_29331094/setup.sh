#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/app_config/incoming
    mkdir -p /home/user/app_config/history
    mkdir -p /home/user/app_config/active

    # Create initial JSON file
    cat << 'EOF' > /home/user/app_config/incoming/v2_update.json
{
  "database_host": "db.internal.net",
  "max_connections": 150,
  "feature_x": "true",
  "timeout_ms": 5000
}
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
