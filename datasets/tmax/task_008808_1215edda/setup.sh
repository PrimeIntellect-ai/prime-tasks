#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc git expect cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/alerts.git
    git init --bare /home/user/alerts.git

    mkdir -p /home/user/dummy_repo
    cd /home/user/dummy_repo
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"
    touch initial.txt
    git add initial.txt
    git commit -m "Initial commit"

    chown -R user:user /home/user/alerts.git /home/user/dummy_repo
    chmod -R 777 /home/user
