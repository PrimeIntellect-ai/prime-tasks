#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang nginx
    pip3 install pytest

    # Create required directories
    mkdir -p /app

    # Ensure permissions for agent to edit
    chmod -R 777 /app
    chmod -R 777 /etc/nginx

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
