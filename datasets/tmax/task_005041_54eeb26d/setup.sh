#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git rustc tzdata procps
    pip3 install pytest

    # Set system-wide git configuration for the tests
    git config --system init.defaultBranch master
    git config --system user.email "test@example.com"
    git config --system user.name "Test User"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
