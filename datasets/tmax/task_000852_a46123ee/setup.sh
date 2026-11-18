#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/backup_rule.json
{"source": "/home/user/settings.conf", "mask_key": "SECRET_TOKEN"}
EOF

    cat << 'EOF' > /home/user/settings.conf
USER=admin
DEBUG=true
LOG_LEVEL=info
SECRET_TOKEN=super_secret_12345
DATABASE_URL=postgres://localhost
SECRET_TOKEN_EXTRA=skip
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
