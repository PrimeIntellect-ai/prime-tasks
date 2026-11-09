#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    # Create directories for the task
    mkdir -p /home/user/repo/incoming
    mkdir -p /home/user/repo/objects
    mkdir -p /home/user/repo/by-name

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
