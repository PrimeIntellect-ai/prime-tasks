#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Ensure the home directory is writable
    chmod -R 777 /home/user
