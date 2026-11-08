#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron tzdata
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backup_source
    echo "Database dump successful" > /home/user/backup_source/data.txt
    echo "1688169600 Primary db synced" > /home/user/backup_source/backup.log
    echo "1688256000 Secondary db synced" >> /home/user/backup_source/backup.log

    cd /home/user/backup_source
    tar -czf /home/user/backup.tar.gz data.txt backup.log
    cd /
    rm -rf /home/user/backup_source

    chmod -R 777 /home/user
