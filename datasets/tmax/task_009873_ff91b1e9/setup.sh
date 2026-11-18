#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Configure git globally
    git config --global user.email "agent@example.com"
    git config --global user.name "Agent"

    # Set up the bare repository
    mkdir -p /home/user/targets.git
    cd /home/user/targets.git
    git init --bare

    # Set up the working clone
    mkdir -p /home/user/targets_work
    cd /home/user/targets_work
    git clone /home/user/targets.git .

    # Ensure permissions are correct
    chmod -R 777 /home/user
