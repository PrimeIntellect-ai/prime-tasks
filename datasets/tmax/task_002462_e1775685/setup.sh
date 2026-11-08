#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/server_configs/app1
    mkdir -p /home/user/server_configs/app2/nested
    mkdir -p /home/user/server_configs/ignored

    # Valid file 1 (2023)
    cat << 'EOF' > /home/user/server_configs/app1/backup_a.json
{"app_name": "Auth Service", "config_version": "1.5.2", "settings": {"retry": 3}}
EOF
    touch -d "2023-05-15 10:00:00" /home/user/server_configs/app1/backup_a.json

    # Valid file 2 (2023)
    cat << 'EOF' > /home/user/server_configs/app2/nested/cfg_b.json
{"app_name": "Payment_Gateway", "config_version": "3.0", "settings": {"timeout": 30}}
EOF
    touch -d "2023-11-01 12:30:00" /home/user/server_configs/app2/nested/cfg_b.json

    # Invalid JSON schema (2023)
    cat << 'EOF' > /home/user/server_configs/app1/bad_schema.json
{"service": "Unknown", "version": "1.0"}
EOF
    touch -d "2023-08-20 09:00:00" /home/user/server_configs/app1/bad_schema.json

    # Valid file but wrong year (2024)
    cat << 'EOF' > /home/user/server_configs/ignored/too_new.json
{"app_name": "Cache Layer", "config_version": "2.1", "settings": {}}
EOF
    touch -d "2024-01-15 10:00:00" /home/user/server_configs/ignored/too_new.json

    # Valid file but wrong year (2022)
    cat << 'EOF' > /home/user/server_configs/ignored/too_old.json
{"app_name": "Old DB", "config_version": "0.9", "settings": {}}
EOF
    touch -d "2022-12-30 10:00:00" /home/user/server_configs/ignored/too_old.json

    chown -R user:user /home/user/server_configs
    chmod -R 777 /home/user
