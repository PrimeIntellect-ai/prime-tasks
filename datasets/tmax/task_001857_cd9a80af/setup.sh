#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/configs
    mkdir -p /home/user/backup

    cat << 'EOF' > /home/user/configs/app.conf
name=MyApp
version=1.0.0
EOF

    cat << 'EOF' > /home/user/configs/db.conf
user=admin
password=secret
host=localhost
EOF

    cat << 'EOF' > /home/user/configs/network.conf
ip=192.168.1.100
port=8080
protocol=tcp
EOF

    cat << 'EOF' > /home/user/configs/ui.conf
theme=dark
resolution=1920x1080
EOF

    cat << 'EOF' > /home/user/changes.log
COMMIT: abc1234
AUTHOR: admin
FILES:
 - app.conf
 - db.conf

COMMIT: def5678
AUTHOR: devops
FILES:
 - network.conf
 - ui.conf
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
