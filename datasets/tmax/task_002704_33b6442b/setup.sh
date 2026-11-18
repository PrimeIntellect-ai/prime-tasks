#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ logrotate
    pip3 install pytest

    # Create directories and initial files
    mkdir -p /home/user
    touch /home/user/proxy_active
    chmod +x /home/user/proxy_active

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
