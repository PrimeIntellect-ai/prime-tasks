#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git tar tzdata socat
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup the initial state
    mkdir -p /home/user/source_repo
    cd /home/user/source_repo
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"
    echo "Initial commit" > readme.md
    git add readme.md
    git commit -m "Init"
    cd /home/user
    tar -czf backup.tar.gz -C /home/user source_repo
    rm -rf /home/user/source_repo

    chmod -R 777 /home/user
