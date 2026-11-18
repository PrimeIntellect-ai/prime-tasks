#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tzdata
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_app.log
2023-11-01 09:00:00 [INFO] Service started successfully
2023-11-01 10:15:30 [WARNING] High CPU usage detected
2023-11-01 12:45:00 [CRITICAL] Payment gateway timeout
2023-11-01 13:00:00 [INFO] User login: admin
2023-11-02 01:30:00 [CRITICAL] Disk space critically low on /dev/sda1
2023-11-02 08:45:12 [ERROR] Failed to send email
EOF

    chmod -R 777 /home/user
    chmod 644 /home/user/legacy_app.log
