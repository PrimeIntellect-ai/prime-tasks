#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat tar gzip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/scripts
    mkdir -p /home/user/backups
    mkdir -p /home/user/logs
    mkdir -p /home/user/dashboards/active
    mkdir -p /home/user/dashboards/staging

    # Create active files
    echo '{"title": "CPU", "panels": 4}' > /home/user/dashboards/active/cpu.json
    echo '{"title": "Memory", "panels": 2}' > /home/user/dashboards/active/mem.json

    # Create staging files
    echo '{"title": "CPU V2", "panels": 5}' > /home/user/dashboards/staging/cpu.json
    echo '{"title": "Memory V2", "panels": 3}' > /home/user/dashboards/staging/mem.json
    echo '{"title": "Network", "panels": ' > /home/user/dashboards/staging/network.json

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
