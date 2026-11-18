#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install additional required packages
    apt-get install -y gcc diffutils

    # Create the user
    useradd -m -s /bin/bash user || true

    # Ensure home directory is writable
    chmod -R 777 /home/user
