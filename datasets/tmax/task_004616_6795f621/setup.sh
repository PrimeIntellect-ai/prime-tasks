#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Ensure home directory is accessible
    chmod -R 777 /home/user
