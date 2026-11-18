#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/config_backups

    cat << 'EOF' > /home/user/config_backups/app_server.part1.cfg
# App Server Config
host=127.0.0.1
port=8080
EOF

    cat << 'EOF' > /home/user/config_backups/app_server.part2.cfg
API_KEY=super_secret_123
max_connections=500
EOF

    cat << 'EOF' > /home/user/config_backups/app_server.part3.cfg
timeout=30
password=db_pass_456
EOF

    cat << 'EOF' > /home/user/config_backups/db_config.txt
[database]
engine=postgres
host=10.0.0.5

[credentials]
username=admin
password=secure_pwd_789
api_key=db_api_key_000
EOF

    cat << 'EOF' > /home/user/config_backups/notes.txt
Just some random notes.
Nothing to see here.
EOF

    cat << 'EOF' > /home/user/config_backups/cache.cfg
# Cache config
engine=redis
memory=2G
Password=redis_pass_111
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
