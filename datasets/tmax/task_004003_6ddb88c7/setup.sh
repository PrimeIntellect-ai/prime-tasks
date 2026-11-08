#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git rustc cargo
    pip3 install pytest

    # Create bare git repo
    mkdir -p /home/user
    git init --bare /home/user/metrics-dashboard.git

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
