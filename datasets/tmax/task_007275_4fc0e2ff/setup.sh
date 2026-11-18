#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git golang-go socat
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app.git /home/user/mail /home/user/source

    # Set up the bare remote repository
    cd /home/user/app.git
    git init --bare

    # Set up the source repository
    cd /home/user/source
    git init
    git checkout -b main
    echo "Version 1.0" > version.txt
    git config user.email "test@example.com"
    git config user.name "Test User"
    git add version.txt
    git commit -m "Initial commit"
    git remote add origin /home/user/app.git

    # Set permissions
    chown -R user:user /home/user
    chmod -R 777 /home/user
