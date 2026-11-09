#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar golang-go
    pip3 install pytest

    mkdir -p /home/user/organizer/backups
    mkdir -p /home/user/organizer/output
    mkdir -p /home/user/organizer/extracted

    cd /home/user/organizer/backups

    echo '{"id": 3, "action": "push", "user": "charlie"}' > log_3.json
    echo '{"id": 1, "action": "commit", "user": "alice"}' > log_1.json
    echo '{"id": 2, "action": "build", "user": "bob"}' > log_2.json

    tar -czf internal.tar.gz log_1.json log_2.json log_3.json
    zip data.zip internal.tar.gz

    rm log_1.json log_2.json log_3.json internal.tar.gz

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
