#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required system packages
    apt-get install -y gcc acl openssh-client

    # Create the user
    useradd -m -s /bin/bash user || true

    # Ensure /home/user is writable
    chmod -R 777 /home/user
