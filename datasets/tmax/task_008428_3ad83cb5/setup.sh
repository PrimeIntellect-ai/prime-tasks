#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils tar gzip
    pip3 install pytest

    # Create directory structure
    mkdir -p /home/user/etc/app

    # Create files
    echo "db_port=5432" > /home/user/etc/db.conf
    echo "env: production" > /home/user/etc/app/config.yaml
    head -c 150000 </dev/urandom > /home/user/etc/large.conf
    echo "old data" > /home/user/etc/old.txt

    # Create update.log
    cat << 'EOF' > /home/user/update.log
Update: 001
Status: Success
Files:
/home/user/etc/db.conf
/home/user/etc/missing.conf

Update: 002
Status: Success
Files:
/home/user/etc/app/config.yaml
/home/user/etc/large.conf
/home/user/etc/old.txt
/tmp/unrelated.conf
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
