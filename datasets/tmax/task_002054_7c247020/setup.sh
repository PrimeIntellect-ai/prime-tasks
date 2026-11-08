#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip grep gawk coreutils
    pip3 install pytest

    mkdir -p /home/user/backups
    mkdir -p /home/user/temp_backup_build/etc/certs
    mkdir -p /home/user/temp_backup_build/var/log/app

    cat << 'EOF' > /home/user/temp_backup_build/etc/app_config.conf
PORT=8443
TLS_CERT=etc/certs/app.crt
LOG_DIR=var/log/app
EOF

    echo "-----BEGIN CERTIFICATE-----" > /home/user/temp_backup_build/etc/certs/app.crt
    echo "MOCKCERTIFICATE..." >> /home/user/temp_backup_build/etc/certs/app.crt
    echo "-----END CERTIFICATE-----" >> /home/user/temp_backup_build/etc/certs/app.crt

    echo "192.168.1.1 - - [10/Oct/2023:13:55:36 -0700] \"GET / HTTP/1.1\" 200 2326" > /home/user/temp_backup_build/var/log/app/access.log
    echo "192.168.1.2 - - [10/Oct/2023:13:56:01 -0700] \"POST /api HTTP/1.1\" 200 102" >> /home/user/temp_backup_build/var/log/app/access.log

    cd /home/user/temp_backup_build
    tar -czf /home/user/backups/server_state.tar.gz etc var
    cd /home/user
    rm -rf /home/user/temp_backup_build

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
