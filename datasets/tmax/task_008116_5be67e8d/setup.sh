#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    # Create user and home directory
    useradd -m -s /bin/bash user || true

    # Ensure permissions are correct
    chmod -R 777 /home/user
