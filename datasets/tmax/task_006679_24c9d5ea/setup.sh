#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git curl
    pip3 install pytest requests

    useradd -m -s /bin/bash user || true

    su - user -c "
    mkdir -p /home/user/deployments
    git init --bare /home/user/repo.git
    git clone /home/user/repo.git /home/user/workspace
    cd /home/user/workspace
    git config user.email 'test@example.com'
    git config user.name 'Test User'
    echo 'initial' > README.md
    git add README.md
    git commit -m 'Initial commit'
    git push origin master
    "

    chmod -R 777 /home/user
