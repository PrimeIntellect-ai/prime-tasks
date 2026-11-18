#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git curl logrotate openssl
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create the site repository
    mkdir -p /home/user/site_workspace
    cd /home/user/site_workspace
    git init
    git config --global user.email "user@example.com"
    git config --global user.name "User"
    echo "<h1>Deployment Successful</h1>" > index.html
    git add index.html
    git commit -m "Initial commit"
    git clone --bare /home/user/site_workspace /home/user/site_repo.git
    rm -rf /home/user/site_workspace

    chmod -R 777 /home/user
