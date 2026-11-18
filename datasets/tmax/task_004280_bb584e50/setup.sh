#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the bare git repository
    mkdir -p /home/user/proxy-repo.git
    git init --bare /home/user/proxy-repo.git

    # Set permissions
    chown -R user:user /home/user
    chmod -R 777 /home/user
