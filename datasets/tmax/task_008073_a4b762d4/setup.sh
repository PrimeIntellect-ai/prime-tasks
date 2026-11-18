#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backups
    mkdir -p /tmp/b_a /tmp/b_b /tmp/b_c

    echo '{"status": "ok"}' > /tmp/b_a/meta.json
    tar -czf /home/user/backups/backup_a.tar.gz -C /tmp/b_a meta.json

    echo '{"status": "corrupt"}' > /tmp/b_b/meta.json
    tar -czf /home/user/backups/backup_b.tar.gz -C /tmp/b_b meta.json

    echo "dummy" > /tmp/b_c/data.txt
    tar -czf /home/user/backups/backup_c.tar.gz -C /tmp/b_c data.txt

    rm -rf /tmp/b_a /tmp/b_b /tmp/b_c

    chmod -R 777 /home/user
