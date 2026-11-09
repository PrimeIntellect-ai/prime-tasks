#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/desired_state.json
{
  "containers": [
    {"name": "auth-service", "log_dir": "/home/user/logs/auth-service"},
    {"name": "db-service", "log_dir": "/home/user/logs/db-service"}
  ]
}
EOF

    chmod -R 777 /home/user
