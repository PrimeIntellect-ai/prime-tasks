#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    apt-get install -y cargo nginx curl

    # Create user
    useradd -m -s /bin/bash user || true

    # Permissions
    chmod -R 777 /home/user
