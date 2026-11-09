#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install task-specific Python packages
    pip3 install grpcio grpcio-tools

    # Create required directories and files
    mkdir -p /home/user/math_port
    echo '{"engine_version": "1.7.4"}' > /home/user/config.json

    # Create the user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
