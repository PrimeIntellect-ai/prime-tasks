#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/config_manager/archives
    mkdir -p /home/user/config_manager/versions

    cd /home/user/config_manager

    # Create changelog.txt
    cat << 'EOF' > changelog.txt
Commit: 9f86d081
Date: 2023-10-01
Author: alice
Message: Initial setup

Commit: a1b2c3d4
Date: 2023-10-05
Author: bob
Message: Stable release v2.4

Commit: e5f6g7h8
Date: 2023-10-10
Author: charlie
Message: Experimental features
EOF

    # Create dummy archives
    for hash in 9f86d081 a1b2c3d4 e5f6g7h8; do
        mkdir -p /tmp/dummy_conf_$hash
        if [ "$hash" = "a1b2c3d4" ]; then
            echo "max_connections=1024" > /tmp/dummy_conf_$hash/database.conf
            echo "timeout=30" >> /tmp/dummy_conf_$hash/database.conf
        else
            echo "max_connections=500" > /tmp/dummy_conf_$hash/database.conf
        fi

        cd /tmp
        tar -czf conf_$hash.tar.gz dummy_conf_$hash/
        # Split the archive into chunks
        split -b 100 conf_$hash.tar.gz config.tar.gz.

        # Create the outer tar
        tar -cf /home/user/config_manager/archives/backup_$hash.tar config.tar.gz.*
        rm config.tar.gz.* conf_$hash.tar.gz
        rm -r dummy_conf_$hash
    done

    chown -R user:user /home/user/config_manager
    chmod -R 777 /home/user
