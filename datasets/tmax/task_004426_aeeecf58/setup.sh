#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/configs/app1
    mkdir -p /home/user/configs/app2

    ln -s /home/user/configs /home/user/configs/app1/backup_loop

    cat << 'EOF' > /tmp/settings.utf8
# Config
DEBUG_LEVEL=1
PORT=8080
ENVIRONMENT=staging
NOTES=Café
EOF
    iconv -f UTF-8 -t ISO-8859-1 /tmp/settings.utf8 > /home/user/configs/app1/settings.oldconf

    cat << 'EOF' > /tmp/main.utf8
DEBUG_LEVEL=1
ENVIRONMENT=staging
DB_HOST=localhost
USER=admin
EOF
    iconv -f UTF-8 -t ISO-8859-1 /tmp/main.utf8 > /home/user/configs/app2/main.oldconf

    cat << 'EOF' > /home/user/configs/app2/ignore_me.txt
DEBUG_LEVEL=1
EOF

    chmod -R 777 /home/user
