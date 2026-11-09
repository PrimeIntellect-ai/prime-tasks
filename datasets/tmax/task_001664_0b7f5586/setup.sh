#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create required directories
    mkdir -p /home/user/app_source
    mkdir -p /home/user/releases

    # Ensure permissions
    chmod -R 777 /home/user
