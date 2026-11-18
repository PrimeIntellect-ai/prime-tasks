#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest pyyaml

    useradd -m -s /bin/bash user || true

    # Configure Git system-wide for the verification script
    git config --system user.email "test@example.com"
    git config --system user.name "Test User"
    git config --system init.defaultBranch master

    chmod -R 777 /home/user
