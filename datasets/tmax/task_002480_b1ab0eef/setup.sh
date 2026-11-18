#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak gcc make git wget curl
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/config_update.wav "System configuration update. Change max_retries to 5. Set db_password to alpha bravo charlie. Update cache_size to 1024."

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/base_config.json
{
  "max_retries": 3,
  "db_password": "old_password_123",
  "cache_size": 256,
  "listen_port": 80
}
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
